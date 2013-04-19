#encoding: utf-8

require 'test_helper'

class RemoteGmoTest < Test::Unit::TestCase
  def setup
    @gateway = GmoGateway.new(fixtures(:gmo))

    @amount = 100
    @credit_card = credit_card('4000100011112224')
    @declined_card = credit_card('4000300011112220')
    @clearly_bad_card = credit_card('123123213123')

    @options = {
      :order_id => "aneworder-#{DateTime.current.to_time.to_i}",
      :billing_address => address,
      :description => 'Store Purchase'
    }
  end

  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Success', response.message
  end

  def test_bad_credit_card
    assert response = @gateway.purchase(@amount, @clearly_bad_card, @options)
    assert_failure response
    # invalid credit card details
    assert_equal 'ご入力いただいた情報が正しいかご確認ください。', response.message
  end

  def test_bad_purchase_amount
    assert response = @gateway.purchase(-1, @credit_card, @options)
    assert_failure response
    # invalid credit card details
    assert_equal '利用金額に数字以外の文字が含まれています。', response.message
  end

  # gmo's test server doesn't seem to check when a credit card expires...
  # def test_bad_credit_card_year
  #   @credit_card.year = 0
  #   @credit_card.month = 0
  #   assert response = @gateway.purchase(@amount, @credit_card, @options)
  #   assert_failure response
  #   # invalid credit card details
  #   assert_equal 'ご入力いただいた情報が正しいかご確認ください。', response.message
  # end

  def test_bad_login
    gateway = GmoGateway.new( shop_id: '', password: '' )
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    # no shop id, no password, no shop & password found.
    assert_equal 'ショップIDが指定されていません。, ショップパスワードが指定されていません。, and 指定されたIDとパスワードのショップが存在しません。', response.message
  end

  # def test_authorize_and_capture
  #   amount = @amount
  #   assert auth = @gateway.authorize(amount, @credit_card, @options)
  #   assert_success auth
  #   assert_equal 'Success', auth.message
  #   assert auth.authorization
  #   assert capture = @gateway.capture(amount, auth.authorization)
  #   assert_success capture
  # end

  # def test_failed_capture
  #   assert response = @gateway.capture(@amount, '')
  #   assert_failure response
  #   assert_equal 'REPLACE WITH GATEWAY FAILURE MESSAGE', response.message
  # end

  # def test_invalid_login
  # end
end
