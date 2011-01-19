require File.dirname(__FILE__)+'/interface-reflector'
module Hipe; end
module Hipe::Resizum

  class Cli
    extend InterfaceReflector
    include InterfaceReflector::CliInstanceMethods
    def self.build_interface
      InterfaceReflector::RequestParser.new do |o|
        o.on('-wWIDTH' , '--width WIDTH', 'who hah boo hah')
        o.on('-eHEIGHT', '--height HEIGHT', 'lala fa fa')
        o.on('-h', '--help',    'Display help screen.')
        o.arg('<img> [<img> [...]]', 'the image(s)')
      end
    end
    def default_action; :resize end
    def on_width(w); @c[:w] = digit(w, 'width') end
    def on_height(h); @c[:h] = digit(h, 'height') end
    def resize
      (@c.keys & [:h, :w]).any? or fatal("please specify height or width\n#{invite}")
      @c.out.puts @c.inspect
    end
    def digit str, name
      str =~ /\A\d+\z/ or raise OptionParser::ParseError.new(
        "#{name} must be positive integer, not #{str.inspect}"
      )
      str.to_i
    end
  end
end
