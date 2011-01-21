require File.dirname(__FILE__)+'/interface-reflector'
require File.dirname(__FILE__)+'/subcommands'

module Hipe::InterfaceReflector::Installer
  def self.extended mod
    mod.class_eval do
      extend  ModuleMethods
      include InstanceMethods
    end
  end
  module ModuleMethods
    include ::Hipe::InterfaceReflector::SubcommandsModuleMethods
    def task name, &b
      add_subcommand_definition TaskDef.new(name, &b)
    end
  end
  module InstanceMethods
    include ::Hipe::InterfaceReflector::SubcommandsCliInstanceMethods
  end
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
              @vals[name]
          end
        end
      end
    end
  end
  class TaskDef < DefStruct
    include ::Hipe::InterfaceReflector::SubcommandsCliInstanceMethods
    extend ::Hipe::InterfaceReflector::CommandDefinition
    # nested not yet ?
    def initialize name, &b
      @name = name
      super()
      yield self
    end
    attr_akksessor :desc, :host, :url, :dest
    def desc?; @vals.key? :desc end
    def desc_lines
      (@vals.key?(:desc) ? (@vals[:desc].kind_of?(Array) ? @vals[:desc] :
        [@vals[:desc]] ) : []).map { |s| "  #{s}" }
    end
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
      class << self ; self end.send(:define_method, :parent) { parent }
      @c = parent.execution_context
      @c.err.puts documenting_option_parser.to_s
      @exit_ok = true
    end
  end
end
