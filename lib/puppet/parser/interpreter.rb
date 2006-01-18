# The interepreter's job is to convert from a parsed file to the configuration
# for a given client.  It really doesn't do any work on its own, it just collects
# and calls out to other objects.

require 'puppet'
require 'puppet/parser/parser'
require 'puppet/parser/scope'


module Puppet
    module Parser
        class Interpreter
            attr_accessor :ast, :filetimeout
            # just shorten the constant path a bit, using what amounts to an alias
            AST = Puppet::Parser::AST

            # create our interpreter
            def initialize(hash)
                unless hash.include?(:Manifest)
                    raise Puppet::DevError, "Interpreter was not passed a manifest"
                end

                @file = hash[:Manifest]
                @filetimeout = hash[:ParseCheck] || 15

                @lastchecked = 0

                if hash.include?(:UseNodes)
                    @usenodes = hash[:UseNodes]
                else
                    @usenodes = true
                end

                # Set it to either the value or nil.  This is currently only used
                # by the cfengine module.
                @classes = hash[:Classes] || []

                # Create our parser object
                parsefiles

                evaluate
            end

            def parsedate
                parsefiles()
                @parsedate
            end

            # evaluate our whole tree
            def run(client, facts)
                parsefiles()

                # Really, we should stick multiple names in here
                # but for now just make a simple array
                names = [client]

                # if the client name is fully qualied (which is normally will be)
                # add the short name
                if client =~ /\./
                    names << client.sub(/\..+/,'')
                end

                begin
                    if @usenodes
                        unless client
                            raise Puppet::Error,
                                "Cannot evaluate nodes with a nil client"
                        end

                        # We've already evaluated the AST, in this case
                        retval = @scope.evalnode(names, facts)
                        if classes = @scope.classlist
                            retval.classes = classes
                        end
                        return retval
                    else
                        # We've already evaluated the AST, in this case
                        @scope = Puppet::Parser::Scope.new() # no parent scope
                        @scope.interp = self
                        @scope.type = "puppet"
                        @scope.name = "top"
                        retval = @scope.evaluate(@ast, facts, @classes)
                        if classes = @scope.classlist
                            retval.classes = classes + @classes
                        end
                        return retval
                    end
                    #@ast.evaluate(@scope)
                rescue Puppet::DevError, Puppet::Error, Puppet::ParseError => except
                    #Puppet.err "File %s, line %s: %s" %
                    #    [except.file, except.line, except.message]
                    if Puppet[:debug]
                        puts except.backtrace
                    end
                    #exit(1)
                    raise
                rescue => except
                    error = Puppet::DevError.new("%s: %s" %
                        [except.class, except.message])
                    if Puppet[:debug]
                        puts except.backtrace
                    end
                    raise error
                end
            end

            def scope
                return @scope
            end

            private

            # Evaluate the configuration.  If there aren't any nodes defined, then
            # this doesn't actually do anything, because we have to evaluate the
            # entire configuration each time we get a connect.
            def evaluate

                # FIXME When this produces errors, it should specify which
                # node caused those errors.
                if @usenodes
                    @scope = Puppet::Parser::Scope.new() # no parent scope
                    @scope.name = "top"
                    @scope.type = "puppet"
                    @scope.interp = self
                    Puppet.debug "Nodes defined"
                    @ast.safeevaluate(@scope)
                else
                    Puppet.debug "No nodes defined"
                    return
                end
            end

            def parsefiles
                if defined? @parser
                    # Only check the files every 15 seconds or so, not on
                    # every single connection
                    if (Time.now - @lastchecked).to_i >= @filetimeout.to_i
                        unless @parser.reparse?
                            @lastchecked = Time.now
                            return false
                        end
                    else
                        return
                    end
                end

                unless FileTest.exists?(@file)
                    if @ast
                        return
                    else
                        raise Puppet::Error, "Manifest %s must exist" % @file
                    end
                end

                if defined? @parser
                    Puppet.info "Reloading files"
                end
                # should i be creating a new parser each time...?
                @parser = Puppet::Parser::Parser.new()
                @parser.file = @file
                @ast = @parser.parse

                # Mark when we parsed, so we can check freshness
                @parsedate = Time.now.to_i
                @lastchecked = Time.now

                # Reevaluate the config.  This is what actually replaces the
                # existing scope.
                evaluate
            end
        end
    end
end

# $Id$
