require 'test_helper'
require 'securerandom'
include Warden::Test::Helpers

class TrackingFlowTest < ActionDispatch::IntegrationTest

  def create_track_request
    random_message_id = SecureRandom.hex
    random_tracking_id = SecureRandom.hex
    { message_id: random_message_id,
      tracking_id: random_tracking_id,
      recipients: ['beders@contextsmith.com'],
      sent_at: DateTime.current.to_s}
  end

  test "can create a track request" do
    @user = User.find_by_email('joe.user@org1.com')
    login_as(@user)

    params = create_track_request
    post "/tracking/create", params.to_json, format: 'json'
    logout
    assert_response :success

  end

  test "can track a request" do
    @user = User.find_by_email('joe.user@org1.com')
    login_as(@user)

    params = create_track_request
    post "/tracking/create", params.to_json, format: 'json'
    logout
    get "/track/foo/#{params[:tracking_id]}/some.gif"
    assert_response :success

    te = TrackingEvent.first
    assert(te)
  end

  test "don't track authenticated request" do
    @user = User.find_by_email('joe.user@org1.com')
    login_as(@user)
    params = create_track_request
    post "/tracking/create", params.to_json, format: 'json'
    get "/track/foo/#{params[:tracking_id]}/some.gif"
    assert_response :success

    te = TrackingEvent.first
    assert_nil(te)
  end

  # test "the truth" do
  #   assert true
  # end
end
