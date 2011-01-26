#!/usr/bin/env ruby
# puts "\e[5;35mruby-debug\e[0m"; require 'rubygems'; require 'ruby-debug'

require 'test/unit'
require 'test/unit/collector'
require 'stringio'

here = File.dirname(__FILE__)
require here + '/interface-reflector'
require here + '/subcommands'


# library and core extib start
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
  def clear_both!
    @err.rewind; @out.rewind
    @err.truncate(0); @out.truncate(0)
  end
end
# library and core extib end

# test case and setup support start
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
  module MyTestCase
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
      cls.nil? and return nil
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
      app.nil? and return
      app.execution_context.clear_both!
      app.execution_context.clear
      app.instance_variable_set('@exit_ok', nil)
    end
    def app
      self.class.app
    end
    def assert_serr args, want
      _assert_sout_or_serr "err", args, want
    end
    def assert_sout args, want
      _assert_sout_or_serr "out", args, want
    end
    def _assert_sout_or_serr which, args, want
      app.run args
      have = app.execution_context.send("flush_#{which}")
      assert_equal_strings have, want
    end
    def assert_equal_strings have, want
      if have == want
        assert_equal want, have
      else
        $stderr.puts "want:#{'<'*20}\n#{linus(want)}80"
        $stderr.puts "have:#{'>'*20}\n#{linus(have)}DONEDONE\n\n"
        assert(false, 'Strings were not equal.')
      end
    end
    def linus str
      str.gsub("\n", "XXX\n")
    end
    def prepare_app *a
      self.class.prepare_app(*a)
    end
  end
end
# test case and setup support end

module Hipe::InterfaceReflectorTests
  class SimpleApp
    extend Hipe::InterfaceReflector
    include Hipe::InterfaceReflector::CliInstanceMethods
    def self.build_interface
      Hipe::InterfaceReflector::RequestParser.new do |o|
        o.on('-h', '--help', 'foobie doobie')
        o.on('-n', '--num FOO', 'some number', :default => 10)
        o.on('-v', '--version', 'show version number')
        o.arg('<foo>', "it's foo")
        o.arg('<bar>', "it's bar")
        o.arg('[<baz> [<baz> [..]]]', "baz is a glob")
      end
    end
    def default_action; :go end
    def go
      @c[:num] == '13' and fatal("must never be 13")
      pl = [@c[:foo], @c[:bar], * (@c[:baz] || [])]
      @c.out.puts "Payload: #{pl.map(&:inspect).join(', ')}."
      :who_hah
    end
    def version_string; 'verzion123' end
  end

  class SimpleAppTests < Test::Unit::TestCase
    extend MyTestCase
    app_class SimpleApp
    program_name 'simp.rb'
    def test_nothing
      assert_serr [], <<-S.unindent
        expecting: <foo> and <bar>
        usage: simp.rb [-h] [-n] [-v] <foo> <bar> [<baz> [<baz> [..]]]
        simp.rb -h for help
      S
    end
    def test_minus_h
      assert_serr %w(-h), <<-S.unindent
        usage: simp.rb [-h] [-n] [-v] <foo> <bar> [<baz> [<baz> [..]]]
        options:
            -h, --help                       foobie doobie
            -n, --num FOO                    some number (default: 10)
            -v, --version                    show version number
        arguments:
            <foo>                            it's foo
            <bar>                            it's bar
            <baz>                            baz is a glob
      S
    end
    def test_minus_h_plus_argument_runs_the_thing
      resp = app.run(%w(-h fiz biz))
      assert_equal :who_hah, resp
      assert_equal_strings app.c.flush_err, <<-S.unindent
        usage: simp.rb [-h] [-n] [-v] <foo> <bar> [<baz> [<baz> [..]]]
        options:
            -h, --help                       foobie doobie
            -n, --num FOO                    some number (default: 10)
            -v, --version                    show version number
        arguments:
            <foo>                            it's foo
            <bar>                            it's bar
            <baz>                            baz is a glob
      S
      assert_equal_strings app.c.flush_out, "Payload: \"fiz\", \"biz\".\n"
    end
    def test_option_with_arg_with_no_handler
      app.run %w(-n 12 foo bar)
      assert_equal '12', app.execution_context[:num]
    end
    def test_file_utils_get
      m = ::Hipe::InterfaceReflector::InstanceMethods
      fu = app.file_utils
      assert_equal m::FileUtilsAdapter, fu.class
      hold = fu.object_id
      assert_equal hold, app.file_utils.object_id
      app.instance_variable_set('@file_utils', nil)
      assert_not_equal hold, app.file_utils
    end
    def test_oxford_comma
      m = Object.new.extend(Hipe::InterfaceReflector::InstanceMethods)
      assert_equal('', m.oxford_comma([]) )
      assert_equal('one', m.oxford_comma(%w(one)))
      assert_equal('one and two', m.oxford_comma(%w(one two)))
      assert_equal('one, two and three', m.oxford_comma(%w(one two three)))
      assert_equal('a, b, c and d', m.oxford_comma(%w(a b c d)))
    end
    def test_throw_and_catch_a_fatal
      assert_serr %w(-n 13 foo bar), <<-S.unindent
        must never be 13
      S
    end
    def test_globby
      assert_sout %w(alpha beta gamma wamma), <<-S.unindent
        Payload: "alpha", "beta", "gamma", "wamma".
      S
    end
    def test_missing_required_arg
      app = self.class.prepare_app(Class.new.class_eval do
        extend Hipe::InterfaceReflector
        include Hipe::InterfaceReflector::CliInstanceMethods
        interface { }
        self
      end, 'anon.rb')
      app.run %w(boingo foingo)
      assert_equal_strings(app.c.flush_err, <<-S.unindent)
        unexpected args: "boingo" and "foingo"
        usage: anon.rb
        anon.rb -h for help
      S
    end
    def test_displaying_default_with_no_description
      app = prepare_app(Class.new.class_eval do
        extend Hipe::InterfaceReflector
        include Hipe::InterfaceReflector::CliInstanceMethods
        interface do |i|
          i.on('-x', '--xxx', :default => 'x-val')
          i.on('-h', '--help', 'show hoidy doighty')
        end
        def default_action; :hallo end
        def hallo; end
        self
      end, 'anon.rb')
      app.run %w(-h)
      assert_equal_strings app.c.flush_err, <<-S.unindent
        usage: anon.rb [-x] [-h]
        options:
            -x, --xxx                        default: "x-val"
            -h, --help                       show hoidy doighty
      S
    end
    def test_version
      app = prepare_app(Class.new.class_eval do
        extend Hipe::InterfaceReflector
        include Hipe::InterfaceReflector::CliInstanceMethods
        interface do |i|
          i.on('-v', '--version', 'shows version string')
        end
        def default_action; :hallo end
        def version_string; '0.1.2' end
        def hallo; end
        self
      end, 'anon-version.rb')
      app.run %w(-v)
      assert_equal_strings app.c.flush_err, <<-S.unindent
        anon-version.rb 0.1.2
      S
    end
  end

  class SimpleSubcommandApp
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

  class SimpleSubcommandAppTests < Test::Unit::TestCase
    extend MyTestCase
    app_class SimpleSubcommandApp
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

  class EdgySubber
    extend Hipe::InterfaceReflector::SubcommandsCli
    on :foo do |o|
      o.desc "in one line i am foo"
      o.interface do |p|
        p.on '-h', '--help', 'helf'
        p.arg('arg1')
        o.execute{ "i am foo" }
      end
    end
    on :fap do |o|
      o.desc "my name is {my_name}."
      o.define(:my_name){ 'fap' }
      o.interface do |p|
      end
    end
    def on_fap; "i am fap" end
  end

  class EdgeCaseSubcommandTests < Test::Unit::TestCase
    extend MyTestCase
    app_class EdgySubber
    program_name 'e-sub.rb'

    # def test_build_documenting_option_parser_for_commmand_wo_subs
    # end
    # def test_has_no_subcommands
    # end
    def test_invalid_subcommand
      app.run %w(zeta)
      str = app.execution_context.flush_err
      assert_match(/Invalid subcommand "zeta"\. +expecting: foo or fap/i, str)
    end
    def test_subcommand_help_ignores_other_options
      app.run %w(-h foo -m)
      str = app.execution_context.flush_err
      assert_match(/ignoring: "-m"/, str)
    end
    def test_one_line_description
      app.run(%w(-h foo))
      str = app.execution_context.flush_err
      assert_match(/^description: in one line i am foo$/, str)
    end
    def test_template_caching
      cls = Class.new.class_eval do
        extend Hipe::InterfaceReflector::SubcommandsCli
        on(:blah) do |o|
          o.desc "whaz:{whiz}"
          o.define(:whiz){ 'whaz' }
        end
        self
      end
      cmd, _ = cls.new.find_subcommand('blah')
      assert_equal "whaz:{whiz}", cmd.desc
      c = cmd.new
      assert_equal nil, c.instance_variable_get('@values')
      assert_equal "whaz:whaz", c.desc
      assert_kind_of Hash, (v = c.instance_variable_get('@values'))
      assert_kind_of Hipe::InterfaceReflector::Templite, v[:desc]
      assert_equal "whaz:whaz", c.desc
      cmd.define(:whiz){'whut'}
      assert_equal "whaz:whut", c.desc
    end
    def test_inspect_anonymous_command_class
      app = EdgySubber.new
      cmd, _ = app.find_subcommand('foo')
      assert_equal(
        'Hipe::InterfaceReflectorTests::EdgySubber::Foo', cmd.inspect)
    end
    def test_execution_setter
      r = app.run %w(foo a1)
      assert_equal "i am foo", r
    end
    def test_defined_method_for_subcommand_implementation
      r = app.run %w(fap)
      assert_equal "i am fap", r
    end
    def test_fuzzy_match
      r = app.run %w(f)
      s = app.execution_context.flush_err
      assert_match(/Invalid subcommand "f"\. +did you mean foo or fap\?/i, s)
    end
    def test_interface_getting
      me = self
      Class.new.class_eval do
        extend Hipe::InterfaceReflector::SubcommandsCli
        on(:blah) do |o|
          i = o.interface
          me.assert_kind_of(Hipe::InterfaceReflector::RequestParser, i)
          i2 = o.interface
          me.assert_kind_of(Hipe::InterfaceReflector::RequestParser, i2)
          me.assert_equal(i.object_id, i2.object_id)
        end
      end
    end
    def test_interface_redefining
      app = Class.new.class_eval do
        extend Hipe::InterfaceReflector::SubcommandsCli
        on(:blah) do |o|
          o.interface { }
          o.interface { }
        end
        self
      end
      e = assert_raises(::RuntimeError) do
        app.new.find_subcommand('blah')
      end
      assert_match(/interface merging not supported!/, e.message)
    end
  end
  class TempliteTests < Test::Unit::TestCase
    extend MyTestCase
    def test_templite
      require File.dirname(__FILE__) + '/templite'
      t = Hipe::InterfaceReflector::Templite.new('goofy:{doofy}:loofy')
      o = Class.new.class_eval do
        def doofy; 'foofy' end
        self
      end.new
      assert_equal 'goofy:foofy:loofy', t.render(o)
    end
    def test_templite_parse_fail
      e = assert_raises(::RuntimeError) do
        Hipe::InterfaceReflector::Templite.new('uh{oh')
      end
      assert_equal "can't parse pattern: \"{oh\"", e.message
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
