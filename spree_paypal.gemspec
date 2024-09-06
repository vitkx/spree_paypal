# frozen_string_literal: true

require_relative "lib/spree_paypal/version"

Gem::Specification.new do |spec|
  spec.name = "spree_paypal"
  spec.version = SpreePaypal::VERSION
  spec.authors = ["vitkx"]
  spec.email = ["vitoxxx1206@gmail.com"]

  spec.summary = "Paypal integration for spree"
  spec.description = "Provides Paypal payment integration for spree"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.add_dependency "spree", "~> 4.9"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
