require 'openssl'
require 'puppet'
require 'puppet/parser/interpreter'
require 'puppet/sslcertificates'
require 'xmlrpc/server'
require 'yaml'

module Puppet
class Server
    class MasterError < Puppet::Error; end
    class Master < Handler
        attr_accessor :ast, :local
        attr_reader :ca

        @interface = XMLRPC::Service::Interface.new("puppetmaster") { |iface|
                iface.add_method("string getconfig(string)")
                iface.add_method("int freshness()")
        }

        def filetimeout
            @interpreter.filetimeout
        end

        def filetimeout=(int)
            @interpreter.filetimeout = int
        end

        # Tell a client whether there's a fresh config for it
        def freshness(client = nil, clientip = nil)
            if defined? @interpreter
                return @interpreter.parsedate
            else
                return 0
            end
        end

        def initialize(hash = {})

            # FIXME this should all be s/:File/:Manifest/g or something
            # build our AST
            @file = hash[:File] || Puppet[:manifest]
            hash.delete(:File)

            if hash[:Local]
                @local = hash[:Local]
            else
                @local = false
            end

            if hash.include?(:CA) and hash[:CA]
                @ca = Puppet::SSLCertificates::CA.new()
            else
                @ca = nil
            end

            @parsecheck = hash[:FileTimeout] || 15

            Puppet.debug("Creating interpreter")

            args = {:Manifest => @file, :ParseCheck => @parsecheck}

            if hash.include?(:UseNodes)
                args[:UseNodes] = hash[:UseNodes]
            elsif @local
                args[:UseNodes] = false
            end

            # This is only used by the cfengine module
            if hash.include?(:Classes)
                args[:Classes] = hash[:Classes]
            end

            begin
                @interpreter = Puppet::Parser::Interpreter.new(args)
            rescue => detail
                Puppet.err detail
                raise
            end
        end

        def getconfig(facts, format = "marshal", client = nil, clientip = nil)
            if @local
                # we don't need to do anything, since we should already
                # have raw objects
                Puppet.debug "Our client is local"
            else
                Puppet.debug "Our client is remote"

                # XXX this should definitely be done in the protocol, somehow
                case format
                when "marshal":
                    begin
                        facts = Marshal::load(CGI.unescape(facts))
                    rescue => detail
                        raise XMLRPC::FaultException.new(
                            1, "Could not rebuild facts"
                        )
                    end
                when "yaml":
                    begin
                        facts = YAML.load(CGI.unescape(facts))
                    rescue => detail
                        raise XMLRPC::FaultException.new(
                            1, "Could not rebuild facts"
                        )
                    end
                else
                    raise XMLRPC::FaultException.new(
                        1, "Unavailable config format %s" % format
                    )
                end
            end

            unless client
                client = facts["hostname"]
                clientip = facts["ipaddress"]
            end
            Puppet.debug("Running interpreter")
            begin
                retobjects = @interpreter.run(client, facts)
            rescue Puppet::Error => detail
                Puppet.err detail
                raise XMLRPC::FaultException.new(
                    1, detail.to_s
                )
            rescue => detail
                Puppet.err detail.to_s
                return ""
            end

            if @local
                return retobjects
            else
                str = nil
                case format
                when "marshal":
                    str = Marshal::dump(retobjects)
                when "yaml":
                    str = YAML.dump(retobjects)
                else
                    raise XMLRPC::FaultException.new(
                        1, "Unavailable config format %s" % format
                    )
                end
                return CGI.escape(str)
            end
        end
    end
end
end
