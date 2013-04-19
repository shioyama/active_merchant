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

      # notes:
      # payment "methods"
      #
      # 1: One time payment ( we only use this )
      # 2: Installment payment,
      # 3: One time payment by bonus,
      # 4: Installment payment by bonus,
      # 5: revolving payment
      #
      # apparently /(e|m)11010999/ 'errors' are successes lol.

      def initialize(options = {})
        requires!(options, :shop_id, :password)
        super
      end

      def prepare( money, order_id )
        post = {}
        add_money( post, money )
        add_order( post, order_id )

        # not sure if this only authorizes a payment. i can't call AUTH then CAPTURE
        # on the same order id. i get an error along the lines of can't ask for money
        # twice on the same order id and there is no difference in the response when
        # using AUTH or CAPTURE. GMOPaymentCC uses AUTH so i'll use AUTH.
        post[:JobCd] = 'AUTH'

        commit 'prepare', post
      end

      def purchase(money, credit_card, options = {})
        requires!(options, :order_id)
        order_id = options[:order_id]

        # creates the order on gmos server
        response = prepare money, order_id

        if successful_prepare? response
          post = {}
          add_credit_card( post, credit_card )
          add_credentials( post, response )
          add_order( post, order_id )

          # see payment method notes
          post[:Method] = 1

          response = commit 'pay', post

          raise [response.inspect, post].inspect

          if successful_payment? response
            # i guess this is a success? :x
            return Response.new true, "Success", response, { :test => test? }
          end
        end

        Response.new false, response[:errors], response, { :test => test? }
      end

      private

      def commit( action_name, params={} )
        gateway_url = action( action_name )
        data = post_data( params )

        response = parse( ssl_post( gateway_url, data ) )

        if response[:ErrInfo].present?
          errors = gmo_errors(response[:ErrInfo])

          puts "\n-------------------------------------------------"
          puts errors
          puts "-------------------------------------------------"

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
        puts "\n-----------PARSING------------------------"
        puts string
        puts "------------------------------------------"
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
        post[:Amount] = money
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

