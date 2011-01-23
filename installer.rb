here = File.dirname(__FILE__)
require here + '/interface-reflector'
require here + '/subcommands'
require here + '/templite'
require 'net/http'

module Hipe::InterfaceReflector::Installer

  def self.extended mod
    mod.class_eval do
      extend  InstallerModuleMethods
      include InstallerInstanceMethods
    end
  end
  module InstallerModuleMethods
    include ::Hipe::InterfaceReflector::DispatcherModuleMethods
    def task name, &b
      add_subcommand_definition TaskDef.new(name, &b)
    end
  end
  module InstallerInstanceMethods
    include ::Hipe::InterfaceReflector::DispatcherCliInstanceMethods
  end
  Templite = Hipe::InterfaceReflector::Templite
  class DefStruct
    def initialize
      @vals = {}
    end
    attr_reader :vals
    class << self
      def attr_akksessor *names
        names.each do |name|
          define_method(name) do |*a|
            a.any? ? @vals[name] = (a.size == 1 ? a.first : a) :
            begin
              v = @vals[name]
              if v.kind_of?(String) && v.index('{')
                (@vals[name] = Templite.new(v)).render(self)
              elsif v.kind_of?(Array) && [String] == v.map(&:class).uniq
                v.map { |x| x.index('{') ? Templite.new(x).render(self) : x }
              elsif v.kind_of?(Templite)
                v.render self
              else
                v
              end
            end
          end
        end
      end
    end
  end
  class TaskDef < DefStruct
    include ::Hipe::InterfaceReflector::CliInstanceMethods # the order ..
    extend ::Hipe::InterfaceReflector::CommandDefinition   # is important!
    # nested not yet ?
    def initialize name, &b
      @name = name
      super()
      yield self
    end
    attr_akksessor :desc, :host, :url, :dest
    def desc?; @vals.key? :desc end
    def desc_lines
      case d = desc
      when NilClass ; []
      when Array ; d
      else [d]
      end
    end
    def default_action; :execute end
    def execute
      if ([:host, :url, :dest] - @vals.keys).empty?
        execute_wget host, url, dest
      else
        fail("don't know what to do with: #{@vals.keys.join(', ')}")
      end
    end

    # wget-type installation begin
    def execute_wget host, url, dest
      File.exist?(dest) and return @c.err.puts("exists: #{dest}")
      @c.err.print "getting http://#{host}#{url}\n"
      len = 0;
      if ! @c.key?(:dry_run) || ! @c[:dry_run]
        File.open(dest, 'w') do |fh|
          res = Net::HTTP.start(host) do |http|
            http.get(url) do |str|
              @c.err.print '.'
              len += str.size
              fh.write str
            end
          end
        end
      end
      @c.err.puts "\nwrote #{dest} (#{len} bytes)."
      true
    end

    def dest_dirname_basename;          File.basename(File.dirname(dest)) end
    def target_basename;                              File.basename(dest) end

    def on_dry_run; @c[:dry_run] = true end

    # wget-type installation end

    def render_desc o
      if desc_lines.size > 1
        o.separator(em("description:"))
        desc_lines.each { |l| o.separator(l) }
        o.separator ''
      else
        o.separator(em("description: ") << desc_lines.first)
      end
    end
    def usage_syntax_string
      [ "#{parent.parent_usage} #{name.to_s}",
        options_syntax_string,
        arguments_syntax_string
      ].compact*' '
    end
    def usage
      # unlike overridee, we don't want to put the usage: string
      usage_syntax_string
    end
    def show_help parent, argv
      # forget children tasks in argv for now
      self.parent = parent
      @c = parent.execution_context
      @c.err.puts documenting_option_parser.to_s
      @exit_ok = true
    end
  end
end
