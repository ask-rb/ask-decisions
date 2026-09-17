require_relative "lib/ask/decisions/version"

Gem::Specification.new do |spec|
  spec.name = "ask-decisions"
  spec.version = Ask::Decisions::VERSION
  spec.authors = ["Kaka Ruto"]
  spec.email = ["kaka@myrrlabs.com"]

  spec.summary = "Decision primitives and providers for the ask-rb ecosystem"
  spec.description = "Typed questions (Choice, Score, Noul) with calibrated probabilities " \
                     "and confidence. Ships with a TypeSafe/Jev provider. Swap providers " \
                     "via the DecisionProvider registry."
  spec.homepage = "https://github.com/ask-rb/ask-decisions"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "ask-core", ">= 0.11.4"
  spec.add_dependency "ask-auth"
  spec.add_dependency "faraday", ">= 2.0"
  spec.add_dependency "json"

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "mocha", "~> 3.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.add_development_dependency "vcr", "~> 6.0"
end
