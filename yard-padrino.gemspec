# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'yard/padrino/version'

Gem::Specification.new do |spec|
  spec.name          = "yard-padrino"
  spec.version       = YARD::Padrino::VERSION
  spec.authors       = ["ITO Nobuaki"]
  spec.email         = ["daydream.trippers@gmail.com"]
  spec.description   = %q{YARD plugin for Padrino controllers.}
  spec.summary       = %q{YARD plugin for Padrino controllers.}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = [
    "yard-padrino.gemspec",
    "Gemfile",
    "LICENSE.txt",
    "README.md",
    "Rakefile",
    "lib/yard-padrino.rb",
    "lib/yard/padrino/version.rb",
    "lib/yard/padrino.rb",
  ]

  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "yard"

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
