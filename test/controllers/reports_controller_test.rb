require 'test_helper'

class ReportsControllerTest < ActionController::TestCase
  test "should get customer" do
    get :customer
    assert_response :success
  end

  test "should get team" do
    get :team
    assert_response :success
  end

  test "should get lifecycle" do
    get :lifecycle
    assert_response :success
  end

end
