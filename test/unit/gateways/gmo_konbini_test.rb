#encoding: utf-8
require 'test_helper'

class GmoKonbiniTest < Test::Unit::TestCase
  def setup
    @gateway = GmoKonbiniGateway.new(:shop_id => 'login', :password => 'password',
                                     :shop_name => 'shop name', :shop_phone => '0300000000',
                                     :shop_hours => '1 hour' )
  end

  def test_encode_shift_jis
    assert_equal '高橋'.encode('Shift_JIS'), @gateway.send(:encode_shift_jis, '髙橋')
  end
end
