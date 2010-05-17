require 'benchmark'
module MongoMapper
  module Plugins
    module QueryLogger

      module ClassMethods
        def find_one(options={})
          criteria, query_options = to_query(options)
          log(query_options.inspect, 'find_one') do
            super
          end
        end

        def find_many(options={})
          criteria, query_options = to_query(options)
          log(query_options.inspect, 'find_many') do
            super
          end
        end

        def log_info(query, name, ms)
          if @logger && @logger.debug?
            name = '%s (%.1fms)' % [name || 'query', ms]
            @logger.debug(format_log_entry(name, query))
          end
        end

        def log(query, name)
          if block_given?
            result = nil
            ms = Benchmark.ms { result = yield }
            @runtime += ms
            log_info(query, name, ms)
            result
          else
            log_info(query, name, 0)
            nil
          end
        end
        
        def format_log_entry(message, dump = nil)
          if true # ActiveRecord::Base.colorize_logging
            if @@row_even
              @@row_even = false
              message_color, dump_color = "4;36;1", "0;1"
            else
              @@row_even = true
              message_color, dump_color = "4;35;1", "0"
            end

            log_entry = "  \e[#{message_color}m#{message}\e[0m   "
            log_entry << "\e[#{dump_color}m%#{String === dump ? 's' : 'p'}\e[0m" % dump if dump
            log_entry
          else
            "%s  %s" % [message, dump]
          end
        end
        
      end
    end
  end
end
