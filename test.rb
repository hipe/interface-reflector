#!/usr/bin/env ruby
# puts "\e[5;35mruby-debug\e[0m"; require 'rubygems'; require 'ruby-debug'

require 'test/unit/testcase'
require 'stringio'

here = File.dirname(__FILE__)
require here + '/interface-reflector'
require here + '/subcommands'

class NeverSee
  extend ::Hipe::InterfaceReflector::SubcommandsCli

  on :foo do |t|
    t.desc 'get foobie and do doobie', 'doible foible'
    t.option_parser do |o|
      o.on '-n', '--dry-run', 'dry run'
    end
  end
  def on_foo
    @c.out.puts "running foo"
    PP.pp(@c, @c.out)
  end
  on :"bar-baz" do |t|
    t.option_parser do |o|
      o.on '-n', '--noigle', 'poigle'
    end
  end
  def on_bar_baz
    @c.out.puts "running bar baz"
    PP.pp(@c, @c.out)
  end
end
class String
  def unindent
    (md = match(/\A( +)/)) ? gsub(/^#{md[1]}/, '') : self
  end
end
module Hipe::InterfaceReflectorTests
  class Foobie < Test::Unit::TestCase
    class << self
      def color_off!
        ::Hipe::InterfaceReflector::CliInstanceMethods.
          send(:define_method, :color){ |a, *b| a }
        @color_off = true
      end
      def app # just to be cute we do this stupid thing
        @app ||= begin
          @color_off or color_off!
          a = NeverSee.new
          a.program_name = 'foo.rb'
          a.c = (ctx = a.build_context)
          ctx.instance_variable_set('@err', StringIO.new)
          def ctx.flush_err
            @err.rewind
            s = @err.read
            @err.rewind
            @err.truncate(0)
            s
          end
          a
        end
      end
    end
    def setup
      app.execution_context.clear
      app.instance_variable_set('@exit_ok', nil)
    end
    def app
      self.class.app
    end
    def assert_serr args, want
      app.run args
      have = app.execution_context.flush_err
      if have == want
        assert_equal want, have
      else
        $stderr.puts "want:#{'<'*20}\n#{linus(want)}DONEDONE"
        $stderr.puts "have:#{'>'*20}\n#{linus(have)}DONEDONE\n\n"
        assert(false, 'Strings were not equal.')
      end
    end
    def linus str
      str.gsub("\n", "XXX\n")
    end
    def test_nothing
      assert_serr [], <<-S.unindent
        expecting subcommand: foo or bar-baz
        usage: foo.rb [-h [<subcommand>]] [ foo | bar-baz ] [opts] [args]
        foo.rb -h for help
      S
    end
    def test_wrong_something
      assert_serr %w(xxx), <<-S.unindent
        Invalid subcommand "xxx". expecting: foo or bar-baz.
        usage: foo.rb [-h [<subcommand>]] [ foo | bar-baz ] [opts] [args]
        foo.rb -h for help
      S
    end
    def test_minus_h
      assert_serr %w(-h), <<-S.unindent
        usage: foo.rb [-h [<subcommand>]] [ foo | bar-baz ] [opts] [args]
        options:
            -h, --help [<subcommand>]        show this screen
        subcommands:
            foo                              get foobie and do doobie
                                             doible foible
            bar-baz
      S
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  require 'test/unit/ui/console/testrunner'
  Test::Unit::UI::Console::TestRunner.new(
    Hipe::InterfaceReflectorTests::Foobie,
    Test::Unit::UI::VERBOSE
  )
end
