require 'test_helper'

class EventControllerTest < ActionController::TestCase
  test "should get select_date" do
    get :select_date
    assert_response :success
  end

  test "should get select_game" do
    get :select_game
    assert_response :success
  end

  test "should get show" do
    get :show
    assert_response :success
  end

end
