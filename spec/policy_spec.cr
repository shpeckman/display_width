# spec/policy_spec.cr
require "./spec_helper"

describe DisplayWidth::Policy do
  it "defaults to graphemes, escape sequences and narrow ambiguous code points" do
    policy = DisplayWidth::Policy.new
    policy.ambiguous.should eq(1)
    policy.graphemes?.should be_true
    policy.escapes?.should be_true
  end

  it "turns escape sequences off" do
    DisplayWidth::Policy.new(escapes: false).escapes?.should be_false
  end

  it "rejects other ambiguous widths" do
    expect_raises(ArgumentError, "ambiguous width must be 1 or 2, not 3") { DisplayWidth::Policy.new(ambiguous: 3) }
    expect_raises(ArgumentError) { DisplayWidth::Policy.new(ambiguous: 0) }
  end
end
