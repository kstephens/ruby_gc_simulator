
task :default => 'ruby_gc_simulator/index.html'

file 'ruby_gc_simulator/index.html' => 'ruby_gc_simulator.textile' do
  sh "../scarlet/bin/scarlet -f html ruby_gc_simulator.textile"
  sh "open ruby_gc_simulator/index.html"
end

file 'ruby_gc_simulator.textile' => 'ruby_gc_simulator.rb' do
  sh "ruby ruby_gc_simulator.rb > ruby_gc_simulator.textile"
end
