#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates that the curated cookbook method lists in
# `Library/Homebrew/rubocops/shared/api_annotation_helper.rb`
# stay in sync with their sources of truth:
#
# - FORMULA_COOKBOOK_METHODS must include every method linked via
#   `/rubydoc/` URLs in `docs/Formula-Cookbook.md`.
# - CASK_COOKBOOK_METHODS must include every `@api public` method
#   defined in the cask source files.
#
# Run from the repository root:
#   ruby .github/check_cookbook_method_lists.rb

require "pathname"
require "set"

HOMEBREW_DIR = Pathname(__dir__).parent/"Library/Homebrew"
HELPER_PATH  = HOMEBREW_DIR/"rubocops/shared/api_annotation_helper.rb"

# Extract method names from a named constant hash in the helper file.
# Looks for lines like `"method_name" => "file.rb"` between the
# constant declaration and `.freeze`.
def methods_from_constant(constant_name)
  helper = HELPER_PATH.read
  block = helper[/#{Regexp.escape(constant_name)}\s*=.*?\{(.*?)\.freeze/m, 1]
  return Set.new if block.nil?

  block.scan(/"(\w+[!?]?)"/).flatten.reject { |m| m.end_with?(".rb") }.to_set
end

# Extract method names linked via rubydoc URLs in a markdown file.
# Pattern: /rubydoc/Class.html#method_name-{class,instance}_method
def rubydoc_methods(cookbook_path)
  content = cookbook_path.read
  content.scan(%r{/rubydoc/\w+(?:/\w+)*\.html#(\w+[!?]?)-(class|instance)_method})
         .map(&:first).to_set
end

# Extract method names that have `# @api public` annotations in a Ruby
# source file. Scans forward from each annotation to find the
# def/attr_reader/delegate that follows.
def api_public_methods(source_path)
  methods = Set.new
  lines = source_path.readlines
  lines.each_with_index do |line, idx|
    next if line.strip != "# @api public"

    (1..5).each do |offset|
      target = lines[idx + offset]&.strip
      break if target.nil? || target.empty?

      m = target.match(/\A(?:def\s+(?:self\.)?|attr_reader\s+:|attr_accessor\s+:)(\w+[!?]?)/) ||
          target.match(/\Adelegate\s+(\w+[!?]?):/)
      if m
        methods.add(m[1])
        break
      end
    end
  end
  methods
end

failed = false

# --- Formula Cookbook ---
cookbook_methods = rubydoc_methods(Pathname(__dir__).parent/"docs/Formula-Cookbook.md")
formula_list    = methods_from_constant("FORMULA_COOKBOOK_METHODS")
missing_formula = (cookbook_methods - formula_list).sort

if missing_formula.any?
  $stderr.puts "::error::Formula Cookbook references methods not in FORMULA_COOKBOOK_METHODS."
  $stderr.puts "These methods have rubydoc links in docs/Formula-Cookbook.md but are"
  $stderr.puts "missing from FORMULA_COOKBOOK_METHODS in #{HELPER_PATH.relative_path_from(Pathname.pwd)}:"
  missing_formula.each { |m| $stderr.puts "  #{m}" }
  failed = true
end

# --- Cask Cookbook ---
cask_list = methods_from_constant("CASK_COOKBOOK_METHODS")
%w[cask/dsl.rb cask/cask.rb cask/dsl/version.rb].each do |src|
  source_methods = api_public_methods(HOMEBREW_DIR/src)
  missing_cask = (source_methods - cask_list).sort
  next if missing_cask.empty?

  $stderr.puts "::error::#{src} has @api public methods not in CASK_COOKBOOK_METHODS."
  $stderr.puts "Add these methods to CASK_COOKBOOK_METHODS in #{HELPER_PATH.relative_path_from(Pathname.pwd)}:"
  missing_cask.each { |m| $stderr.puts "  #{m}" }
  failed = true
end

exit 1 if failed
puts "Cookbook method lists are in sync."
