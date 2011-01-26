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
    include ::Hipe::InterfaceReflector::SubcommandModuleMethods
    def task name, &b
      add_subcommand_definition TaskDef.create_subclass(name, self, &b)
    end
  end
  module InstallerInstanceMethods
    include ::Hipe::InterfaceReflector::SubcommandCliInstanceMethods
  end
  Templite = Hipe::InterfaceReflector::Templite
  class DefStruct
    def initialize
      @vals = {}
    end
    attr_reader :vals
    class << self
      def defaults; @defaults ||= {} end
      def attr_akksessor *names
        mm = class << self ; self end
        names.each do |name|
          mm.send(:define_method, name) do |*a|
            a.any? ? defaults[name] = (a.size == 1 ? a.first : a) : begin
              defaults[name]
            end
          end
          define_method(name) do |*a|
            a.any? ? @vals[name] = (a.size == 1 ? a.first : a) :
            begin
              v = @vals.key?(name) ? @vals[name] : self.class.defaults[name]
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
    include ::Hipe::InterfaceReflector::SubcommandCliInstanceMethods #order ..
    extend ::Hipe::InterfaceReflector::CommandDefinitionClass # is important!
    attr_akksessor :desc, :host, :url, :dest
    # nested not yet ?
    class << self
      attr_accessor :name
      def constantize name
        name.to_s.sub(/^[^a-z]/i, '').gsub(/[^a-z0-9_]/, '').
          sub(/^([a-z])/){ $1.upcase }.intern
      end
      def create_subclass name, namespace_module, &b
        k = constantize name
        namespace_module.const_defined?(k) and fail("already have: #{k}")
        kls = Class.new TaskDef
        kls.name = name
        class << kls; self end.send(:define_method, :inspect) do
          "#{namespace_module.inspect}::#{k}"
        end
        yield(kls)
        namespace_module.const_set(k, kls)
        kls
      end
    end

    def desc?; @vals.key?(:desc) || self.class.defaults.key?(:desc) end
    def desc_lines
      case d = desc
      when NilClass ; []
      when Array ; d
      else [d]
      end
    end
    def default_action; :execute end
    def execute
      keys = @vals.keys | self.class.defaults.keys
      if ([:host, :url, :dest] - keys).empty?
        execute_wget host, url, dest
      else
        fail("don't know what to do with: #{keys.join(', ')}")
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
      [ subcommand_fully_qualified_name,
        options_syntax_string,
        arguments_syntax_string
      ].compact*' '
    end
  end
end
