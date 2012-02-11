
task :default => :slides

desc "Generate slides."
task :slides => 'slides/index.html'

file 'ruby_gc_simulator' do
  sh "ln -s slides ruby_gc_simulator"
end

file 'slides/index.html' => 'slides.textile' do
  sh "../scarlet/bin/scarlet -f html slides.textile"
  sh "open slides/index.html" if ENV['open']
end

file 'slides.textile' => 'ruby_gc_simulator.rb' do
  sh "ruby ruby_gc_simulator.rb > slides.textile"
end

desc "Publish slides."
task :publish => [ :slides ] do
  sh "rsync $RSYNC_OPTS -aruzv --delete-excluded --delete --exclude='.git' --exclude='.riterate' ./ kscom:kurtstephens.com/pub/ruby/#{File.basename(File.dirname(__FILE__))}/"
end
