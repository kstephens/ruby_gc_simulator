
task :default => :slides

desc "Generate slides."
task :slides => 'ruby_gc_simulator/index.html'

file 'ruby_gc_simulator/index.html' => 'ruby_gc_simulator.textile' do
  sh "../scarlet/bin/scarlet -f html ruby_gc_simulator.textile"
  sh "open ruby_gc_simulator/index.html"
end

file 'ruby_gc_simulator.textile' => 'ruby_gc_simulator.rb' do
  sh "ruby ruby_gc_simulator.rb > ruby_gc_simulator.textile"
end

desc "Publish slides."
task :publish => [ :slides ] do
  sh "rsync $RSYNC_OPTS -aruzv --delete-excluded --delete --exclude='.git' --exclude='.riterate' ./ kscom:kurtstephens.com/pub/ruby/#{File.basename(File.dirname(__FILE__))}/"
end
