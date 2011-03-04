require File.dirname(__FILE__) + '/interface-reflector'
require File.dirname(__FILE__) + '/subcommands'
module Hipe::InterfaceReflector
  module Tasks
    include SubcommandCliModuleMethods
    def self.extended mod
      mod.class_eval do
        include SubcommandCliInstanceMethods
      end
    end
    def task name, &b
      if instance_variable_defined?('@subcommands') && @subcommands
        @subcommands.push(task_class.create_subclass(name, self, &b))
      else
        @subcommand_blocks ||= []
        @subcommand_blocks.push(proc{
          task_class.create_subclass(name, self, &b)
        })
      end
    end
    def task_class cls=nil, &b
      if block_given?
        cls and raise ArgumentError.new("don't give class and block")
        @task_class = nil
        @task_class_block = b
      elsif cls
        @task_class = cls
        @task_class_block = nil
      elsif instance_variable_defined?('@task_class_block') &&
          @task_class_block
        @task_class_block.call
      elsif instance_variable_defined?('@task_class')
        @task_class
      else
        TaskDefinition
      end
    end
  end
  class TaskDefinition < CommandDefinition
    include SubcommandCliInstanceMethods
    class << self
      def task_class(*a)
        return command_class(*a)
      end
      def depends_on(*a)
        @depends_on ||= []
        a.any? ? @depends_on.concat(a) : @depends_on
      end
      def describe_deps # for templates for descriptions
        depends_on.map(&:inspect).join(', ')
      end
    end
    # @todo this is in huge need of some testing out the wazoo
    def run_deps
      self.class.depends_on.empty? and
        return error("#{self.class.intern.inspect} has no dependencies " <<
          "and no definition.")
      self.class.depends_on.each do |cmd_sym|
        # there is a huge resason we do self.class.parent and not
        # self.parent.class, it is devil reason.
        cmd_cls = self.class.parent.subcommand(cmd_sym)
        cmd_cls or return error("dependee for #{self.class.intern.inspect} "<<
          "not defined: #{cmd_sym.inspect}")
        cmd = cmd_cls.subcommand_execution_instance
        cmd.execution_context = @c
        cmd.parent = self # be very careful, this could cause pain !!! @todo
        cmd.run @argv # meh!!!
      end
    end
    def execute
      found_something_to_do = false
      ret = nil
      if self.class.depends_on.any?
        found_something_to_do = true
        run_deps
      end
      if parent.respond_to? as_method_name
        found_something_to_do = true
        ret = command_definition_execute
      end
      unless found_something_to_do
        msg = "#{self.class.name.inspect} has no dependencies to run " <<
          "and cmd.execute{...} was not used to define an implementation"
        unless parent.kind_of? Tasks::RakelikeRunner
          msg << " and #{parent.class.name} did not define "<<
            " #{self.as_method_name}()"
        end
        error msg<<'.'
      end
      ret
    end
  end
  module CommandDefinitionModuleMethods
    def run_deps_then_execute &b
      define_method(:execute) do
        run_deps
        b.call(* (b.arity == 1 ? [self] : []))
      end
    end
    def run_deps_then_instance_eval &b
      define_method(:execute) do
        run_deps
        instance_eval(&b)
      end
    end
    def run_deps_then_run_unbound unbound
      define_method(:execute) do
        run_deps
        unbound.bind(self).call
      end
    end
  end
end
# experimental below!!
module Hipe::InterfaceReflector
  module Tasks
    class RakelikeRunner
      extend ::Hipe::InterfaceReflector::Tasks
      class << self
        attr_accessor :next_desc
      end
    end
    class << self
      attr_reader :rakelike
      alias_method :rakelike?, :rakelike
      def rakelike!
        instance_variable_defined?('@rakelike') && @rakelike and return false
        @rakelike = true
        self.const_set(:RakelikeGlobalTaskSpace,
          Class.new(RakelikeRunner).class_eval { self }
        )
        Kernel.at_exit do
          if $!
            $stderr.puts "(inteface reflector skipping task execution. "<<
              "there were errors (#{$!.class})..)"
          elsif RakelikeGlobalTaskSpace.subcommands.nil?
            $stderr.puts "interface reflector: no tasks defined "<<
              "in #{$PROGRAM_NAME}."
          else
            RakelikeGlobalTaskSpace.new.run(ARGV)
          end
        end
        Kernel.send(:define_method, :task, &RakelikeTaskDefiner)
        Kernel.send(:define_method, :desc, &RakelikeDescDefiner)
      end
      RakelikeDescDefiner = lambda do |*a|
        all_tasks = RakelikeGlobalTaskSpace
        all_tasks.next_desc ||= []
        all_tasks.next_desc.concat a
      end
      module RakelikeHelper
        extend self
        def parse_names_and_deps mixed
          if mixed.kind_of?(::Symbol)
            name = mixed
            deps = []
          elsif mixed.kind_of?(::Hash) && mixed.length == 1
            name = mixed.keys.first
            deps = mixed[name];
            deps.kind_of?(Array) or deps = [deps]
          else
            raise ArgumentError.new(
              "task name must be of format :name or :name => :dep or "<<
              ":name => [:dep1, :dep2 [..]], not #{mixed.inspect}")
          end
          [name, deps]
        end
      end
      RakelikeTaskDefiner = lambda do |mixed, &block|
        all_tasks = RakelikeGlobalTaskSpace
        name, deps = RakelikeHelper.parse_names_and_deps(mixed)
        block.nil? and deps.empty? and raise ArgumentError.new(
          "No definition provided for #{name.inspect}.  "<<
          "For now this means nothing."
        )
        :default == name and all_tasks.default_subcommand(:default)
        next_desc = all_tasks.next_desc
        all_tasks.next_desc = nil
        def_blk2 = exe_block = nil
        if block
          if 1 == block.arity
            def_blk2 = block
          else
            exe_block = block
          end
        end
        all_tasks.task(name) do |o|
          def_blk2  and def_blk2.call(o)
          next_desc and o.desc(* (next_desc + (o.desc.nil? ? [] :
            (o.desc.kind_of?(Array) ? o.desc : [o.desc]))))
          deps.any? and o.depends_on(*deps)
          if exe_block
            if deps.any?
              # o.run_deps_then_execute(&exe_block)
              o.run_deps_then_instance_eval(&exe_block)
            else
              o.execute(&exe_block)
            end
          elsif o.execute_defined? && deps.any?
            o.run_deps_then_run_unbound(o.instance_method(:execute))
          end
        end
      end
    end
  end
end
