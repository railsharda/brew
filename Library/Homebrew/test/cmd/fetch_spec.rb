# typed: false
# frozen_string_literal: true

require "cmd/fetch"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::FetchCmd do
  it_behaves_like "parseable arguments"

  it "downloads the Formula's URL", :integration_test do
    setup_test_formula "testball"

    expect { brew "fetch", "testball" }.to be_a_success

    expect(HOMEBREW_CACHE/"testball--0.1.tbz").to be_a_symlink
    expect(HOMEBREW_CACHE/"testball--0.1.tbz").to exist
  end

  it "concurrently downloads formula URLs", :integration_test do
    setup_test_formula "testball1"
    setup_test_formula "testball2"

    expect { brew "fetch", "testball1", "testball2", "HOMEBREW_DOWNLOAD_CONCURRENCY" => "2" }.to be_a_success

    expect(HOMEBREW_CACHE/"testball1--0.1.tbz").to be_a_symlink
    expect(HOMEBREW_CACHE/"testball1--0.1.tbz").to exist
    expect(HOMEBREW_CACHE/"testball2--0.1.tbz").to be_a_symlink
    expect(HOMEBREW_CACHE/"testball2--0.1.tbz").to exist
  end

  it "fails before downloading a cask when HOMEBREW_CASK_OPTS_REQUIRE_SHA is set", :integration_test do
    expect do
      brew "fetch", "--cask", cask_path("no-checksum"), "HOMEBREW_CASK_OPTS_REQUIRE_SHA" => "1"
    end.to output(/--require-sha/).to_stderr
                                  .and not_to_output(/Downloading/).to_stdout
                                                                   .and be_a_failure
  end
end
