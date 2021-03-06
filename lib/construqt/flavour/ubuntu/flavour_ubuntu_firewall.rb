module Construqt
  module Flavour
    module Ubuntu

      module Firewall
        class ToFrom
          include Util::Chainable
          chainable_attr_value :begin, nil
          chainable_attr_value :begin_to, nil
          chainable_attr_value :begin_from, nil
          chainable_attr_value :middle, nil
          chainable_attr_value :middle_to, nil
          chainable_attr_value :middle_from, nil
          chainable_attr_value :end, nil
          chainable_attr_value :end_to, nil
          chainable_attr_value :end_from, nil
          chainable_attr_value :factory, nil
          chainable_attr_value :ifname, nil
          chainable_attr_value :interface, nil
          chainable_attr :output_only, true, false
          chainable_attr :input_only, true, false
          chainable_attr_value :output_ifname_direction, "-i"
          chainable_attr_value :input_ifname_direction, "-o"

          def only_in_out(rule)
            output_only rule.output_only?
            input_only rule.input_only?
            self
          end

          def space_before(str)
            if str.nil? or str.empty?
              ""
            else
              " "+str.strip
            end
          end

          def push_begin_to(str)
            begin_to(get_begin_to + space_before(str))
          end

          def push_begin_from(str)
            begin_from(get_begin_from + space_before(str))
          end

          def push_middle_to(str)
            middle_to(get_middle_to + space_before(str))
          end

          def push_middle_from(str)
            middle_from(get_middle_from + space_before(str))
          end

          def push_end_to(str)
            end_to(get_end_to + space_before(str))
          end

          def push_end_from(str)
            end_from(get_end_from + space_before(str))
          end

          def get_begin_to
            return space_before(@begin_to) if @begin_to
            return space_before(@begin)
          end

          def get_begin_from
            return space_before(@begin_from) if @begin_from
            return space_before(@begin)
          end

          def get_middle_to
            return space_before(@middle_to) if @middle_to
            return space_before(@middle)
          end

          def get_middle_from
            return space_before(@middle_from) if @middle_from
            return space_before(@middle)
          end

          def get_end_to
            return space_before(@end_to) if @end_to
            return space_before(@end)
          end

          def get_end_from
            return space_before(@end_from) if @end_from
            return space_before(@end)
          end

          def bind_interface(ifname, iface, rule)
            self.interface(iface)
            self.ifname(ifname)
            if rule.from_is_inbound?
              output_ifname_direction("-i")
              input_ifname_direction("-o")
            else
              output_ifname_direction("-o")
              input_ifname_direction("-i")
            end
          end

          def output_ifname
            return space_before("#{@output_ifname_direction} #{@ifname}") if @ifname
            return ""
          end

          def input_ifname
            return space_before("#{@input_ifname_direction} #{@ifname}") if @ifname
            return ""
          end

          def has_to?
            @begin || @begin_to || @middle || @middle_to || @end || @end_to
          end

          def has_from?
            @begin || @begin_from || @middle || @middle_from || @end || @end_from
          end

          def factory!
            get_factory.create
          end
        end

        def self.write_table(iptables, rule, to_from)
          family = iptables=="ip6tables" ? Construqt::Addresses::IPV6 : Construqt::Addresses::IPV4
          if rule.from_interface?
            #binding.pry
            from_list = IPAddress::IPv4::summarize(
              *(iptables=="ip6tables" ? to_from.get_interface.address.v6s : to_from.get_interface.address.v4s).map do |adr|
                adr.to_string
              end)
          else
            from_list = Construqt::Tags.ips_net(rule.get_from_net, family)
          end

          to_list = Construqt::Tags.ips_net(rule.get_to_net, family)
          #puts ">>>>>#{from_list.inspect}"
          #puts ">>>>>#{state.inspect} end_to:#{state.end_to}:#{state.end_from}:#{state.middle_to}#{state.middle_from}"
          action_i = action_o = rule.get_action
          if to_list.empty? && from_list.empty?
            #puts "write_table=>o:#{to_from.output_only?}:#{to_from.output_ifname} i:#{to_from.input_only?}:#{to_from.input_ifname}"
            if to_from.output_only?
              to_from.factory!.row("#{to_from.output_ifname}#{to_from.get_begin_from}#{to_from.get_middle_to} -j #{rule.get_action}#{to_from.get_end_to}")
            end

            if to_from.input_only?
              to_from.factory!.row("#{to_from.input_ifname}#{to_from.get_begin_to}#{to_from.get_middle_from} -j #{rule.get_action}#{to_from.get_end_from}")
            end
          end

          if to_list.length > 1
            action_o = "I.#{to_from.get_ifname}.#{rule.object_id.to_s(32)}"
            action_i = "O.#{to_from.get_ifname}.#{rule.object_id.to_s(32)}"
            to_list.each do |ip|
              if to_from.output_only?
                to_from.factory!.table(action_o).row("#{to_from.output_ifname} -d #{ip.to_string} -j #{rule.get_action}")
              end

              if to_from.input_only?
                to_from.factory!.table(action_i).row("#{to_from.input_ifname} -s #{ip.to_string} -j #{rule.get_action}")
              end
            end

          elsif to_list.length == 1
            from_dst = " -d #{to_list.first.to_string}"
            to_src = " -s #{to_list.first.to_string}"
          else
            from_dst = to_src =""
          end

          from_list.each do |ip|
            if to_from.output_only?
              to_from.factory!.row("#{to_from.output_ifname}#{to_from.get_begin_from} -s #{ip.to_string}#{from_dst}#{to_from.get_middle_from} -j #{action_o}#{to_from.get_end_to}")
            end

            if to_from.input_only?
              to_from.factory!.row("#{to_from.input_ifname}#{to_from.get_begin_to}#{to_src} -d #{ip.to_string}#{to_from.get_middle_to} -j #{action_i}#{to_from.get_end_from}")
            end
          end
        end

        def self.write_raw(raw, ifname, iface, writer)
          #        puts ">>>RAW #{iface.name} #{raw.firewall.name}"
          raw.rules.each do |rule|
            throw "ACTION must set #{ifname}" unless rule.get_action
            if rule.prerouting?
              to_from = ToFrom.new.bind_interface(ifname, iface, rule).only_in_out(rule)
              #puts "PREROUTING #{to_from.inspect}"
              write_table("iptables", rule, to_from.factory(writer.ipv4.prerouting))
              write_table("ip6tables", rule, to_from.factory(writer.ipv6.prerouting))
            end

            if rule.output?
              to_from = ToFrom.new.bind_interface(ifname, iface, rule).only_in_out(rule)
              write_table("iptables", rule, to_from.factory(writer.ipv4.output))
              write_table("ip6tables", rule, to_from.factory(writer.ipv6.output))
            end
          end
        end

        def self.write_nat(nat, ifname, iface, writer)
          nat.rules.each do |rule|
            throw "ACTION must set #{ifname}" unless rule.get_action
            throw "TO_SOURCE must set #{ifname}" unless rule.to_source?
            if rule.to_source? && rule.postrouting?
              src = iface.address.ips.select{|ip| ip.ipv4?}.first
              throw "missing ipv4 address and postrouting and to_source is used #{ifname}" unless src
              to_from = ToFrom.new.only_in_out(rule).end_to("--to-source #{src}")
                .ifname(ifname).factory(writer.ipv4.postrouting)
              write_table("iptables", rule, to_from)
            end
          end
        end

        def self.protocol_loop(rule)
          protocol_loop = []
          if !rule.tcp? && !rule.udp?
            protocol_loop << ''
          else
            protocol_loop << '-p tcp' if rule.tcp?
            protocol_loop << '-p udp' if rule.udp?
          end

          protocol_loop
        end

        def self.write_forward(forward, ifname, iface, writer)
          forward.rules.each do |rule|
            throw "ACTION must set #{ifname}" unless rule.get_action
            #puts "write_forward #{rule.inspect} #{rule.input_only?} #{rule.output_only?}"
            if rule.get_log
              to_from = ToFrom.new.bind_interface(ifname, iface, rule).only_in_out(rule)
                .end_to("--nflog-prefix o:#{rule.get_log}:#{ifname}")
                .end_from("--nflog-prefix i:#{rule.get_log}:#{ifname}")
              write_table("iptables", rule.clone.action("NFLOG"), to_from.factory(writer.ipv4.forward))
              write_table("ip6tables", rule.clone.action("NFLOG"), to_from.factory(writer.ipv6.forward))
            end

            protocol_loop(rule).each do |protocol|
              #binding.pry
              to_from = ToFrom.new.bind_interface(ifname, iface, rule).only_in_out(rule)
              to_from.push_begin_to(protocol)
              to_from.push_begin_from(protocol)
              if rule.get_ports && !rule.get_ports.empty?
                to_from.push_middle_from("-dports #{rule.get_ports.join(",")}")
                to_from.push_middle_to("-dports #{rule.get_ports.join(",")}")
              end

              if rule.connection?
                to_from.push_middle_from("-m state --state NEW,ESTABLISHED")
                to_from.push_middle_to("-m state --state RELATED,ESTABLISHED")
              end

              write_table("iptables", rule, to_from.factory(writer.ipv4.forward))
              write_table("ip6tables", rule, to_from.factory(writer.ipv6.forward))
            end
          end
        end

        def self.write_host(host, ifname, iface, writer)
          host.rules.each do |rule|
            in_to_from = ToFrom.new.bind_interface(ifname, iface, rule).input_only
            out_to_from = ToFrom.new.bind_interface(ifname, iface, rule).output_only
            if rule.get_log
              #binding.pry
              l_in_to_from = ToFrom.new.bind_interface(ifname, iface, rule).input_only
                .end_to("--nflog-prefix o:#{rule.get_log}:#{ifname}")
              l_out_to_from = ToFrom.new.bind_interface(ifname, iface, rule).output_only
                .end_from("--nflog-prefix i:#{rule.get_log}:#{ifname}")
              write_table("iptables", rule.clone.action("NFLOG"), l_in_to_from.factory(writer.ipv4.input))
              write_table("iptables", rule.clone.action("NFLOG"), l_out_to_from.factory(writer.ipv4.output))
              write_table("ip6tables", rule.clone.action("NFLOG"), l_in_to_from.factory(writer.ipv6.input))
              write_table("ip6tables", rule.clone.action("NFLOG"), l_out_to_from.factory(writer.ipv6.output))
            end

            write_table("iptables", rule, in_to_from.factory(writer.ipv4.input))
            write_table("iptables", rule, out_to_from.factory(writer.ipv4.output))
            write_table("ip6tables", rule, in_to_from.factory(writer.ipv6.input))
            write_table("ip6tables", rule, out_to_from.factory(writer.ipv6.output))
          end
        end

        def self.create(host, ifname, iface)
          throw 'interface must set' unless ifname
          writer = iface.host.result.etc_network_iptables
          iface.firewalls && iface.firewalls.each do |firewall|
            firewall.get_raw && Firewall.write_raw(firewall.get_raw, ifname, iface, writer.raw)
            firewall.get_nat && Firewall.write_nat(firewall.get_nat, ifname, iface, writer.nat)
            firewall.get_forward && Firewall.write_forward(firewall.get_forward, ifname, iface, writer.filter)
            firewall.get_host && Firewall.write_host(firewall.get_host, ifname, iface, writer.filter)
          end
        end
      end
    end
  end
end
