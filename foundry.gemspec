# -*- encoding: utf-8 -*-
require File.expand_path('../lib/foundry/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Peter Zotov"]
  gem.email         = ["whitequark@whitequark.org"]
  gem.description   = %q{Foundry is a hybrid Ruby interpreter/compiler which aims to } <<
                      %q{optimize code speed and footprint for various targets.}
  gem.summary       = gem.description
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "foundry"
  gem.require_paths = ["lib"]
  gem.version       = Foundry::VERSION

  gem.add_dependency "trollop"
  gem.add_dependency "melbourne", '>= 2.0.0.beta1'
  gem.add_dependency "ansi"
end
