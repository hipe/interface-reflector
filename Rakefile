desc "genenerates coverage from tests"
task :rcov do
  require 'open3'
  FileUtils.cd(File.dirname(__FILE__)) do
    output = '../coverage'
    Open3.popen3(
      'rcov', '-x', '^/', '-x', '^test\.rb', '-T', '-o', output, './test.rb'
    ) do |sin, sout, serr|
      $stdout.puts sout.read
      (s = serr.read) == '' or $stderr.puts(s)
    end
    $stdout.puts "wrote #{output}"
  end
end

task :default => :rcov
