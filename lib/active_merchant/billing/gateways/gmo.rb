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
          post[:JobCd] = 'CAPTURE'

          response = commit 'pay', post

          if successful_payment? response
            # i guess this is a success? :x
            return Response.new true, "Success", response, { :test => test? }
          end
        end

        Response.new false, response[:errors], response, { :test => test? }
      end

      def credit(money, authorization, options = {})
        deprecated CREDIT_DEPRECATION_MESSAGE
        refund(money, authorization, options)
      end

      def search( order_id )
        post = {}
        add_order( post, order_id )

        response = commit 'search', post

        successful_search?( response ) ? response : false 
      end

      def refund(money, authorization, options = {})

        if search_response = search(options[:order_id])
          # {:OrderID=>["aneworder1366674734"],
          #  :Status=>["AUTH"],
          #  :ProcessDate=>["20130423085242"],
          #  :JobCd=>["AUTH"],
          #  :AccessID=>["c076e3ffe8165d049812355a3d669550"],
          #  :AccessPass=>["51b4e044a2b0766dfd27181942968bbf"],
          #  :ItemCode=>["0000990"],
          #  :Amount=>["100"],
          #  :Tax=>["0"],
          #  :SiteID=>nil,
          #  :MemberID=>nil,
          #  :CardNo=>["************2224"],
          #  :Expire=>["0914"],
          #  :Method=>["1"],
          #  :PayTimes=>nil,
          #  :Forward=>["2a99662"],
          #  :TranID=>["1304230850111111111111191997"],
          #  :Approve=>["6721293"],
          #  :ClientField1=>nil,
          #  :ClientField2=>nil,
          #  :ClientField3=>nil}
          post = {}

          post[:JobCd] = 'RETURN'
          add_credentials(post, search_response)
          response = commit 'alter', post

          # check accessid, accesspass, trandi, approve?
          if successful_prepare? response
            Response.new true, 'Success', response, { :test => test? }
          else
            # test this some how.
            Response.new false, response[:errors], response, { :test => test? }
          end

          # an example of a response
           # {:AccessID=>["b9c1fa1696a8d9a797e4a165a199238c"], :AccessPass=>["c21e39db4e49cf06516b28f9191d91c7"], :Forward=>["2a99662"], :Approve=>["6721508"], :TranID=>["1304230917111111111111192150"], :TranDate=>["20130423091939"]}

        else
          Response.new false, 'Order ID not found', {}, { :test => test? }
        end

        # # if we have a payment
        # post = {}
        # add_credentials( post, response )
        # # if payment was today -> void
        # # else return
        # post[:JobCd] = 'RETURN'
        # response = commit( 'alter', post )

        # if successful_refund? response

        # end

        # Response.new false, response[:errors], response, { :test => test? }
      end

      private

      def commit( action_name, params={} )
        gateway_url = action( action_name )
        data = post_data( params )

        response = parse( ssl_post( gateway_url, data ) )

        if response[:ErrInfo].present?
          errors = gmo_errors(response[:ErrInfo])

          puts "\nERRORS-------------------------------------------"
          puts errors
          puts "-------------------------------------------------\n"

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

