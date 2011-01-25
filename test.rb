#!/usr/bin/env ruby
# puts "\e[5;35mruby-debug\e[0m"; require 'rubygems'; require 'ruby-debug'

require 'test/unit'
require 'test/unit/collector'
require 'stringio'

here = File.dirname(__FILE__)
require here + '/interface-reflector'
require here + '/subcommands'


class String
  def unindent
    (md = match(/\A( +)/)) ? gsub(/^#{md[1]}/, '') : self
  end
end
class Hipe::InterfaceReflector::GenericContext < Hash
  def _flush it
    it.rewind
    s = it.read
    it.rewind
    it.truncate 0
    s
  end
  def flush_err; _flush @err end
  def flush_out; _flush @out end
end

module Hipe::InterfaceReflectorTests
  class << self
    def color_off!
      @color_off and return
      ::Hipe::InterfaceReflector::CliInstanceMethods.
        send(:define_method, :color){ |a, *b| a }
      @color_off = true
    end
    def common_setup!
      color_off!
    end
  end
  class ModuleCollector
    include ::Test::Unit::Collector
    def initialize mod, name = mod.to_s
      @filters = []
      @name = name
      @module = mod
    end
    def collect
      suite = ::Test::Unit::TestSuite.new @name
      ss = []
      @module.constants.each do |mod|
        ::Test::Unit::TestCase > (m = @module.const_get(mod)) and
          add_suite(ss, m.suite)
      end
      sort(ss).each { |s| suite << s }
      suite
    end
  end
  module TestCaseModuleMethods
    def self.extended mod
      mod.class_eval do
        include TestCaseInstanceMethods
      end
    end
    def app_class cls
      @app_class = cls
    end
    def program_name nm
      @program_name = nm
    end
    def prepare_app cls=@app_class, name=(@program_name || 'foo.rb')
      app = cls.new
      app.program_name = name
      app.c = (ctx = app.build_context)
      ctx.instance_variable_set('@err', StringIO.new)
      ctx.instance_variable_set('@out', StringIO.new)
      app
    end
    def app
      @app ||= prepare_app # this could be really stupid
    end
  end
  module TestCaseInstanceMethods
    def app
      self.class.app
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
  end
end
module Hipe::InterfaceReflectorTests
  class NeverSee
    extend ::Hipe::InterfaceReflector::SubcommandsCli

    on :foo do |t|
      t.desc 'get foobie and do doobie', 'doible foible'
      t.request_parser do |o|
        o.on '-n', '--dry-run', 'dry run'
        o.on '-h', '--help', 'this screen'
      end
    end
    def on_foo
      @c.out.puts "running foo"
      PP.pp(@c, @c.out)
    end
    on :"bar-baz" do |t|
      t.request_parser do |o|
        o.on '-n', '--noigle', 'poigle'
      end
    end
    def on_bar_baz
      @c.out.puts "running bar baz"
      PP.pp(@c, @c.out)
    end
  end
end

module Hipe::InterfaceReflectorTests
  class NeverSeeTests < Test::Unit::TestCase
    extend TestCaseModuleMethods
    app_class NeverSee
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
    def test_minus_h_command
      assert_serr %w(-h fo), <<-S.unindent
        usage: foo.rb foo [-n] [-h]
        description:
        get foobie and do doobie
        doible foible

        options:
            -n, --dry-run                    dry run
            -h, --help                       this screen
      S
    end
    def test_minus_h_with_bad_command
      assert_serr %w(-h fiz), <<-S.unindent
        Invalid subcommand "fiz". expecting: foo or bar-baz.
        usage: foo.rb [-h [<subcommand>]] [ foo | bar-baz ] [opts] [args]
        foo.rb -h for help
      S
    end
    def test_command_minus_h
      assert_serr %w(foo -h), <<-S.unindent
        usage: foo.rb foo [-n] [-h]
        description:
        get foobie and do doobie
        doible foible

        options:
            -n, --dry-run                    dry run
            -h, --help                       this screen
      S
    end
    def test_command_minus_m
      assert_serr %w(foo -m), <<-S.unindent
        invalid option: -m
        usage: foo.rb foo [-n] [-h]
        foo.rb -h for help
      S
    end
  end
end

module Hipe::InterfaceReflectorTests
  class SimpleApp
    extend Hipe::InterfaceReflector
    include Hipe::InterfaceReflector::CliInstanceMethods
    def self.build_interface
      Hipe::InterfaceReflector::RequestParser.new do |o|
        o.on('-h', '--help', 'foobie doobie')
        o.on('-d', '--dry-run', 'drizzle rizzle')
        o.arg('<foo>', "it's foo")
      end
    end
    def default_action; :go end
    def go
      @c.out.puts "Payload."
    end
  end
end

module Hipe::InterfaceReflectorTests
  class SimpleTests < Test::Unit::TestCase
    extend TestCaseModuleMethods
    app_class SimpleApp
    program_name 'simp.rb'
    def test_nothing
      assert_serr [], <<-S.unindent
        expecting: <foo>
        usage: simp.rb [-h] [-d] <foo>
        simp.rb -h for help
      S
    end
  end
end

if 'rcov' == File.basename($PROGRAM_NAME)
  Hipe::InterfaceReflectorTests.common_setup!
  # for no particular reason, we do this cutely, back when we were writing our
  # own runner
  require 'test/unit/ui/console/testrunner'
  m = Hipe::InterfaceReflectorTests
  suites = Hipe::InterfaceReflectorTests::ModuleCollector.new(
    Hipe::InterfaceReflectorTests).collect
  # SILENT PROGRESS_ONLY NORMAL VERBOSE
  Test::Unit::UI::Console::TestRunner.run(suites, Test::Unit::UI::NORMAL)
elsif __FILE__ == $PROGRAM_NAME
  Hipe::InterfaceReflectorTests.common_setup!
  # let autorunner do its magic
else
  Test::Unit.run = true # don't automatically run at exit
end
