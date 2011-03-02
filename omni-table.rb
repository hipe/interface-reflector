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
#       Phone  column 2
#      iphone  329.99
#     android  29.99
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
      @headers = true
      @rows = rows
      @sep = '  '
    end
    attr_reader :cols, :rows, :headers
    alias_method :headers?, :headers
    def no_headers!; @headers = false; self end
    def to_ascii out
      matrix = rendered_matrix
      headers? and matrix.unshift(@cols.map(&:label))
      widths
      matrix.each do |row|
        out.puts(@cols.map do |c|
          m = row[c.intern]
          d = m.respond_to?(:cel_meta) ? m.cel_meta : c
          f = @widths[c.intern] - len(row[c.intern])
          "#{d.fill * f if d.right?}#{m.to_str}#{d.fill * f if d.left?}"
        end.join(@sep))
      end
      out
    end
    def sep *a
      a.empty? and return @sep
      @sep = a.first
      self
    end
    class Col
      def initialize h
        @label = h[:label]
        @align = h[:align] || :right
        @fill  = h[:fill]  || ' '
        if h[:column_index]
          @intern = h[:column_index]
          @label.nil? and @label = "column #{h[:column_index]+1}"
        end
      end
      attr_reader :align, :fill, :intern, :label
      def left?;  @align == :left  end
      def right?; @align == :right end
      def render v
        v.to_str
      end
    end
    class Cel
      def self.build h
        new h
      end
      def initialize h
        @h = h
        @align = h[:align] || :left
        @fill  = h[:fill]  || ' '
      end
      attr_reader :fill
      def cel_meta; self end
      def left?  ; @align == :left  end
      def right? ; @align == :right end
      def to_str
        @h[:value].to_str
      end
    end
  protected
    def len mixed
      s = mixed.to_str
      s.index("\e") or return s.length;
      s.gsub(/\e[^m]+m/, '').length
    end
    def rendered_matrix
      @rendered_matrix ||= begin
        @rows.map do |r|
          @cols.map do |c|
            v = r[c.intern]
            v.kind_of?(Hash) ? Cel.build(v) : c.render(v)
          end
        end
      end
    end
    def widths
      @widths ||= begin
        w = instance_variable_defined?('@header_cels') ?
          Hash[ *
            @header_cels.each.with_index.map { |s,i| [i, len(s)] }.flatten
          ] : Hash.new { |h, k| h[k] = 0 };
        rendered_matrix.each do |row|
          row.each_with_index do |v, i|
            w[i] > len(v) or w[i] = len(v)
          end
        end
        w
      end
    end
  end
end
