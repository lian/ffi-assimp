$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "ffi-assimp"
  s.version     = "0.0.1"
  s.authors     = ["lian", "Sunny"]
  s.email       = ["meta.rb@gmail.com", "sunny@sunfox.org"]

  s.summary     = %q{ffi-assimp and animation helpers}
  s.description = %q{ffi-assimp and animation helpers}
  s.homepage    = "https://github.com/lian/ffi-assimp"

  s.rubyforge_project = "ffi-assimp"

  s.files = `git ls-files`.split("\n")
  s.test_files  = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables =
    `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.required_rubygems_version = ">= 1.3.6"

  s.add_runtime_dependency "ffi"
end
