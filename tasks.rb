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
      if @subcommands
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
      elsif @task_class_block
        @task_class_block.call
      elsif @task_class
        @task_class
      else
        TaskDefinition
      end
    end
  end
  class TaskDefinition < CommandDefinition
  end
end
