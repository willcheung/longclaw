require 'resolv-replace'

dns_resolver = Resolv::DNS.new
dns_resolver.timeouts=10

Resolv::DefaultResolver.replace_resolvers([Resolv::Hosts.new, dns_resolver])