require 'fileutils'
require 'strscan'
require 'rubygems'
require 'RMagick'
require File.dirname(__FILE__)+'/interface-reflector'
module Hipe; end
module Hipe::Resizum
  class Cli
    extend InterfaceReflector, InterfaceReflector::Colorizer
    include InterfaceReflector::CliInstanceMethods
    def self.g x
      color(x, :green)
    end
    def self.build_interface
      InterfaceReflector::RequestParser.new do |o|
        o.on('-wWIDTH' , '--width WIDTH', 'who hah boo hah')
        o.on('-eHEIGHT', '--height HEIGHT', 'lala fa fa')
        o.on('-a', '--aspect-ratio',
          'fit image inside dimensions, maintaining aspect ratio')
        o.on('-n', '--dry-run', 'dry run! write no files')
        o.on('-p', '--mkdirs', 'make directories as necessary (as mkdir -p)')
        o.on('-r', '--recursive', 'descend into directories')
        o.on('-oPATTERN', '--output-pattern PATTERN',
          'how to name the output image file.',
          "(macros available: #{g 'dirname'}, #{g 'basename'}, "<<
          "#{g 'path'})", '',
          :default => '{dirname}/thumbs/{basename}')
        o.on('-mPATTERN', '--move PATTERN', 'move original file to here')
        o.on('-h', '--help',    'Display help screen.')
        o.arg('<img> [<img> [...]]', 'the image(s)')
      end
    end
    def default_action; :dispatch end
    def on_aspect_ratio; @c[:aspect_ratio] = true end
    def on_dry_run; @c[:dry_run] = true end
    def on_height(h); @c[:height] = digit(h, 'height') end
    def on_width(w); @c[:width] = digit(w, 'width') end
    def on_output_pattern(x); @c[:output_pattern] = x end
    def on_mkdirs; @c[:mkdirs] = true end
    def on_move(x); @c[:move] = x end
    def on_recursive; @c[:recursive] = true end
    def dispatch
      @intersect = (@c.keys & [:height, :width])
      @c.key?(:aspect_ratio) and init_aspect_ratio
      case @intersect.size
      when 0 ; return fatal("please specify height or width\n#{invite}")
      when 1 ; @action = :scale
      else     @action = :resize
      end
      @c[:output_pattern] = compile(@c[:output_pattern])
      @c[:move] and @c[:move] = compile(@c[:move])
      do_these @c[:img]
      @c.err.puts "done."
    end
    def init_aspect_ratio
      @intersect.size == 2 or return fatal("aspect ratio setting doesn't"<<
      "make sense unless you specify width and height")
    end
    def do_these paths
      paths.each do |p|
        @_path = p
        if ! File.exist? @_path
          @c.err.puts("file not found, skipping: #{@_path.inspect}")
        elsif File.directory? @_path
          if @c[:recursive]
            do_these Dir["#{@_path}/*"]
          else
            @c.err.puts("is directory, skipping: #{@_path.inspect}")
          end
        else
          do_this
        end
      end
    end
    def do_this
      @_output = @c[:output_pattern].render @_path
      @_outdir = File.dirname @_output
      File.directory?(@_outdir) or no_outdir(@_outdir) or return
      _path = nil
      if @c.key? :move
        _path = @_path
        @_path = move(@_path) or return
      end
      begin
        File.directory?(@_outdir) or no_outdir || return
          # terrible hack so this doesn't break on dry run:
        img = File.exist?(@_path) ? MyImage.new(@_path) : MyImage.new(_path)
        send @action, img, @_output
      rescue Magick::ImageMagickError => e
        @c.err.puts( "encountered error. not image file? skipping" <<
          " #{@_path.inspect} (with message: #{e.message})" )
      end
    end
    Quiet = {} # on dry run, hack it so as to only display things once
    def no_outdir dir
      if @c.key?(:mkdirs)
        if ! Quiet.key?(dir)
          Quiet[dir] = true
          file_utils.mkdir_p(dir, :verbose=>true, :noop=>@c.key?(:dry_run))
        end
        true
      else
        @c.err.puts("target directory (#{dir}) does not exist and -p " <<
        "option is not present. skipping: #{@_path}")
        false
      end
    end
    def move path
      dest = @c[:move].render(path)
      outdir = File.dirname(dest)
      File.directory?(outdir) or (no_outdir(outdir) or return false)
      file_utils.mv(path, dest, :verbose => true, :noop => @c[:dry_run])
      dest
    end
    def compile pattern
      PathTemplite.new pattern
    end
    # width and height were provided
    def resize img, output
      m = img.metrics
      @c[:width] < m[:width] || @c[:height] < m[:height] or
        return too_big_for_resize(img, m)
      if @c.key? :aspect_ratio
        min = [[:width, @c[:width].to_f / m[:width].to_f],
         [:height, @c[:height].to_f / m[:height].to_f]].inject do |a, x|
           a[1] < x[1] ? a : x
        end
        return _scale img, min[1], output, m
      end
      @c.err.puts sprintf('%s ->{%dx%d resized to %dx%d}-> %s',
        img.my_path, m[:width], m[:height], @c[:width], @c[:height], output )
      unless @c.key?(:dry_run)
        img2 = img.resize @c[:width], @c[:height]
        img2.write output
      end
      true
    end
    def scale img, output
      m = img.metrics
      term = @intersect.first
      factor = m[term].to_f / @c[term].to_f
      factor < 1.0 or return too_big_for_scale(img, m, factor, term)
      _scale img, factor, output, m
    end
    def _scale img, factor, output, m
      @c.err.puts sprintf('%s ->{ %dx%d scaled %0.2f%% to %dx%d }-> %s',
        img.my_path, m[:width], m[:height], factor * 100,
        m[:width] * factor, m[:height] * factor, # estimations!
        output)
      unless @c.key?(:dry_run)
        img2 = img.scale factor
        img2.write output
      end
    end
    def too_big_for_resize img, m
      @c.err.puts(sprintf("with #{img.my_path.inspect}: won't make a "<<
        "bigger image. (%dx%d to %dx%d) skipping.",
        m[:width], m[:height], @c[:width], @c[:height]
      ))
      false
    end
    def too_big_for_scale img, m, factor, term
      @c.err.puts(sprintf("won't make a bigger image. "<<
        "(%dx%d to %s:%d (%0.2f%%))", m[:width], m[:height], term.to_s,
        @c[term], factor))
      false
    end
    def digit str, name
      str =~ /\A\d+\z/ or raise OptionParser::ParseError.new(
        "#{name} must be positive integer, not #{str.inspect}"
      )
      str.to_i
    end
  end
  class Templite
    def initialize str
      @str = str
      scn = StringScanner.new(str)
      @parts = []
      until scn.eos?
        if plain = scn.scan(/[^{]+/)
          @parts.push [:plain, plain]
        end
        unless scn.eos?
          if var = scn.scan(/\{[_a-z]+\}/)
            call = /\A\{([_a-z]+)\}\Z/.match(var)[1].intern
            respond_to?("do_#{call}") or
              fail("invalid var: #{call.to_s.inspect}")
            @parts.push [call]
          else
            fail("can't parse pattern: #{scn.rest.inspect}")
          end
        end
      end
    end
    def render thing
      @_thing = thing
      @_out = ""
      @parts.each{ |x| @_out.concat send("do_#{x[0]}", *x[1..-1]) }
      s = @_out
      @_out = @_thing = nil
      s
    end
    def do_plain txt
      txt
    end
  end
  class PathTemplite < Templite
    def do_basename
      File.basename @_thing
    end
    def do_dirname
      File.dirname @_thing
    end
    def do_path
      @_thing
    end
  end

  class MyImage < Magick::ImageList
    def initialize p
      @my_path = p
      super(p)
    end
    attr_reader :my_path
    def metrics
      md = %r{\A\[
        (.+) [ ] ([A-Z]+) [ ] (\d+)x(\d+) [ ] (\d+)x(\d+)\+(\d+)\+(\d+) [ ]
        (DirectClass|PseudoClass) [ ] (\d+)-bit [ ] (\d+)([a-z]+)
      \]\nscene=(\d+)
      \Z}x.match(inspect) or fail("fix this: #{@my_path} #{inspect.inspect}")
      h = Hash[ [:filename, :format, :width, :height, :pwidth, :pheight,
        :x_offset, :y_offset, :class, :bit_depth, :blob_size, :blob_unit,
        :scene
      ].zip(md.captures) ]
      [:width, :height, :pwidth, :pheight, :x_offset, :y_offset, :bit_depth,
      :blob_size, :scene].each{ |k| h.key?(k) and h[k] = h[k].to_i }
      h
    end
  end
end
