require File.dirname(__FILE__) + '/gmo/gmo_errors'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class GmoGateway < Gateway
      include GmoErrors

      self.test_url = 'https://pt01.mul-pay.jp'
      self.live_url = 'https://p01.mul-pay.jp'

      self.supported_countries = ['JA']
      self.supported_cardtypes = [:visa, :master, :jcb, :american_express, :diners_club]
      self.homepage_url = 'http://www.gmo-pg.jp/'
      self.display_name = 'GMO Credit Card'
      self.money_format = :cents
      self.default_currency = 'JPY'

      def initialize(options = {})
        requires!(options, :shop_id, :password)
        super
      end

      def void(order_id, options={})
        if search_response = search(order_id)
          post = {}
          post[:JobCd] = 'VOID'

          add_order( post, order_id )
          add_credentials( post, search_response )

          response = commit 'alter', post

          return Response.new true, 'Success', response, { test: test? }
        end

        Response.new false, 'Order ID not found', {}, { test: test? }
      end

      def purchase(money, credit_card, options = {})
        requires!(options, :order_id)
        order_id = options[:order_id]

        # creates the order on gmos server
        response = prepare money, order_id

        if successful_prepare? response
          post = {}
          post[:Method] = 1
          post[:JobCd] = 'CAPTURE'

          add_credit_card( post, credit_card )
          add_credentials( post, response )
          add_order( post, order_id )

          response = commit 'pay', post

          if successful_payment? response
            # i guess this is a success? :x
            return Response.new true, 'Success', response, { test: test?, authorization: order_id }
          end

          return Response.new false, response[:errors], response, { test: test?, authorization: order_id }
        end

        Response.new false, response[:errors], response, { test: test? }
      end

      def credit(money, authorization, options = {})
        deprecated CREDIT_DEPRECATION_MESSAGE
        refund(money, authorization, options)
      end

      def refund(money, order_id, options = {})
        if search_response = search(order_id)

          # only support full refunds right now.
          if search_response[:Amount].first.to_i != money
            return Response.new false, 'No Partial Refunds', search_response, { test: test? }
          end

          post = {}
          post[:JobCd] = 'RETURN'
          add_credentials(post, search_response)

          response = commit 'alter', post

          # appropriate response -> success
          if successful_prepare? response
            return Response.new true, 'Success', response, { test: test? }
          end

          # test this some how.
          return Response.new false, response[:errors], response, { test: test? }
        end

        Response.new false, 'Order ID not found', {}, { test: test? }
      end

      private

      def prepare( money, order_id )
        post = {}
        post[:JobCd] = 'CAPTURE'

        add_money( post, money )
        add_order( post, order_id )

        commit 'prepare', post
      end

      def search( order_id )
        post = {}
        add_order( post, order_id )

        response = commit 'search', post

        successful_search?( response ) ? response : false
      end

      def commit( action_name, params={} )
        gateway_url = action( action_name )
        data = post_data( params )

        response = parse( ssl_post( gateway_url, data ) )

        if response[:ErrInfo].present?
          errors = gmo_errors(response[:ErrInfo])

          response[:errors] = errors
        end

        return response
      end

      def action_uri( name )
        case name
        when 'prepare'
          '/payment/EntryTran.idPass'
        when 'pay'
          '/payment/ExecTran.idPass'
        when 'alter'
          '/payment/AlterTran.idPass'
        when 'change'
          '/payment/ChangeTran.idPass'
        when 'search'
          '/payment/SearchTrade.idPass'
        else
          raise "GMO Action #{name} is unsupported"
        end
      end

      def action( name )
        path = action_uri name
        url = test? ? test_url : live_url

        "#{url}#{path}"
      end

      # gmo gives us key value pairs in the format of
      # Key=Value|Value|Value&Key2=Value
      def parse( string )
        data = {}

        pairs = string.split('&')
        pairs.each do |kv|
          key, values = kv.split('=')
          data[key.to_sym] = values.nil? ? nil : values.split('|')
        end

        data
      end

      def expiry credit_card
        year  = format(credit_card.year, :two_digits)
        month = format(credit_card.month, :two_digits)
        "#{month}#{year}"
      end

      def add_money( post, money )
        post[:Amount] = amount(money)
      end

      def add_order( post, order_id )
        post[:OrderID] = order_id
      end

      def add_credit_card( post, credit_card )
        post[:CardNo] = credit_card.number
        post[:Expire] = expiry(credit_card)
        post[:SecurityCode] = credit_card.verification_value
      end

      def add_credentials( post, prepare_response )
        post[:AccessID] = prepare_response[:AccessID].first
        post[:AccessPass] = prepare_response[:AccessPass].first
      end

      def successful_search? response
        successful_response?(response) &&
        successful_prepare?(response) &&
        successful_payment?(response) &&
        response[:JobCd].present? &&
        response[:Amount].present? &&
        response[:Tax].present?
      end

      def successful_prepare? response
        successful_response?(response) &&
        response[:AccessID].present? &&
        response[:AccessPass].present?
      end

      def successful_payment? response
        successful_response?(response) &&
        response[:Approve].present? &&
        response[:TranID].present?
      end

      def successful_response? response
        response.is_a? Hash
      end

      def post_data(params = {})
        post = {}

        post[:ShopID] = @options[:shop_id]
        post[:ShopPass] = @options[:password]

        post.merge(params).map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")
      end
    end
  end
end

