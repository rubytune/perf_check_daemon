
require File.expand_path '../test_helper.rb', __FILE__

config.github.hook_secret = nil

class GithubCommentTest < MiniTest::Unit::TestCase
  include Rack::Test::Methods

  def parse_branch(args, branch, newargs)
    x, y = GithubComment.parse_branch(args)
    assert_equal branch, x
    assert_equal newargs, y
  end

  def test_parse_branch
    parse_branch("/abc", nil, "/abc")

    parse_branch("-n10", nil, "-n10")

    parse_branch("-n10 /abc", nil, "-n10 /abc")

    parse_branch("-n10 /abc -rref_branch", nil, "-n10 /abc -rref_branch")

    parse_branch("-n10 /abc --reference xyz", nil, "-n10 /abc --reference xyz")

    parse_branch("-n10 --reference xyz /abc", nil, "-n10 --reference xyz /abc")

    parse_branch("-n10 --ref xyz /abc --ref xyz", nil, "-n10 --ref xyz /abc --ref xyz")

    parse_branch("-n10 --ref xyz /abc --ref ttt", nil, "-n10 --ref xyz /abc --ref ttt")

    parse_branch("/abc --branch abranch", "abranch", "/abc")

    parse_branch("--branch abranch /abc", "abranch", "/abc")

    parse_branch("-n10 --branch abranch", "abranch", "-n10")

    parse_branch("--branch abranch -n10", "abranch", "-n10")

    parse_branch("-n10 --branch abranch /abc", "abranch", "-n10 /abc")

    parse_branch("-n10 /abc -rref_branch --branch abranch", "abranch", "-n10 /abc -rref_branch")

    parse_branch("--branch abranch -n10 /abc --reference xyz", "abranch", "-n10 /abc --reference xyz")

    parse_branch("-n10 --reference xyz --branch abranch /abc", "abranch", "-n10 --reference xyz /abc")

    parse_branch("-n10 --branch abranch --ref xyz /abc --ref xyz", "abranch", "-n10 --ref xyz /abc --ref xyz")

    parse_branch("-n10 --ref xyz /abc --ref ttt --branch abranch", "abranch", "-n10 --ref xyz /abc --ref ttt")
  end
end
