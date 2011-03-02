# = omni table
#
# no dependencies but ruby 1.8.7/1.9.2
#
# == usage
#
#   rows = [['iphone', 329.99], ['android', 29.99]]
#   col_meta = [{:label=>'Phone', :align=>:right}, {:align => :left}]
#
#   Hipe::InterfaceReflector::OmniTable.new(rows, col_meta).to_ascii($stdout)
#
#       Phone column 2
#      iphone 329.99
#     android 29.99
#
# Some setters are available to affect the look of the thing.
# Try: sep(' | ').no_headers! for:
#
#    iphone | 329.99
#   android | 29.99
#
#

module Hipe; end
module Hipe::InterfaceReflector
  class OmniTable
    def initialize rows, cols
      @cols = cols.each.with_index.map do |c,i|
        c.respond_to?(:render) ? c : Col.new({:column_index => i}.merge(c))
      end
      @rows = rows
      @headers = true
    end
    attr_reader :cols, :rows, :headers
    alias_method :headers?, :headers
    def no_headers!; @headers = false; self end
    def to_ascii out
      headers? and out.puts(header_row_text)
      rendered_rows.each do |row|
        out.puts row_printf_format % row
      end
      out
    end
    def header_row_text
      @header_row_text ||= begin
        @header_cels = @cols.map(&:label)
        row_printf_format % @header_cels
      end
    end
    def render_row r
      @cols.map { |c| c.render(r[c.intern]) }
    end
    def rendered_rows
      instance_variable_defined?('@prerendered') ? @prerendered : prerender
    end
    def row_printf_format
      @row_printf_format ||= begin
        @widths = instance_variable_defined?('@header_cels') ?
          Hash[ *
            @header_cels.each.with_index.map { |s,i| [i, s.length] }.flatten
          ] : Hash.new { |h, k| h[k] = 0 };
        rendered_rows.each do |row|
          row.each_with_index do |v, i|
            @widths[i] > v.length or @widths[i] = v.length
          end
        end
        (0..@widths.size-1).map do |i|
          "%#{'-' if :left == @cols[i].align}#{@widths[i]}s"
        end.join(sep)
      end
    end
    def sep *a
      if a.any?
        @sep = a.first
        self
      else
        instance_variable_defined?('@sep') ? @sep : ' '
      end
    end
    class Col
      def initialize h
        @label = h[:label]
        @align = h[:align] || :right
        if h[:column_index]
          @intern = h[:column_index]
          @label.nil? and @label = "column #{h[:column_index]+1}"
        end
      end
      attr_reader :label, :align, :intern
      def render v
        v.to_s
      end
    end
  protected
    def prerender
      @prerendered = @rows.map { |r| render_row(r) }
    end
  end
end
