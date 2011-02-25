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
    def execute *a
      run_deps
    end
  end
  module CommandDefinitionModuleMethods
    def run_deps_then_execute &b
      define_method(:execute) do
        run_deps
        b.call(self)
      end
    end
  end
end
# experimental below!!
module Hipe::InterfaceReflector
  module Tasks
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
      class RakelikeRunner
        extend ::Hipe::InterfaceReflector::Tasks
        class << self
          attr_accessor :next_desc
        end
      end
      RakelikeDescDefiner = lambda do |*a|
        all_tasks = RakelikeGlobalTaskSpace
        all_tasks.next_desc ||= []
        all_tasks.next_desc.concat a
      end
      RakelikeTaskDefiner = lambda do |mixed, &block|
        all_tasks = RakelikeGlobalTaskSpace
        if mixed.kind_of?(::Symbol)
          name = mixed
          deps = []
        elsif mixed.kind_of?(::Hash) && mixed.length == 1
          name = mixed.keys.first
          deps = mixed[name];
          deps.kind_of?(Array) or deps = [deps]
        else
          raise ArgumentError.new(
            "failsauce on task syntax: #{mixed.inspect}")
        end
        if block.nil? && deps.empty?
          raise ArgumentError.new("No definition provided for "<<
            " #{name.inspect}.  For now this means nothing.")
          # all_tasks.subcommands and return all_tasks.subcommand(name)
        end
        if :default == name
          all_tasks.default_subcommand :default
        end
        all_tasks.task(name) do |o|
          if all_tasks.next_desc
            o.desc(*all_tasks.next_desc)
            all_tasks.next_desc = nil
          end
          deps.any? and o.depends_on(*deps)
          if block
            if deps.any?
              o.run_deps_then_execute(&block)
            else
              o.execute(&block)
            end
          end
        end
      end
    end
  end
end
