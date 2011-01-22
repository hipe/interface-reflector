require 'strscan'

module Hipe; end
module Hipe::InterfaceReflector
  class Templite
    def initialize str
      @parts = []
      scn = StringScanner.new str
      until scn.eos?
        if plain = scn.scan(/[^{]+/)
          @parts.push [:plain, plain]
        end
        unless scn.eos?
          if var = scn.scan(/\{[_a-z]+\}/)
            call = /\A\{([_a-z]+)\}\Z/.match(var)[1].intern
            @parts.push [call]
          else
            fail "can't parse pattern: #{scn.rest.inspect}"
          end
        end
      end
    end
    def render thing
      @_thing = thing
      @_out = ""
      @parts.each{ |x| @_out.concat render_value(*x) }
      s = @_out
      @_out = @_thing = nil
      s
    end
    def render_value name, *args
      respond_to?("do_#{name}") ? send("do_#{name}", *args) :
        @_thing.send(name, *args)
    end
    def do_plain txt
      txt
    end
  end
end
