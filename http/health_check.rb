class HealthCheck < Scout::Plugin
  needs 'net/http'
  needs  'uri'

  OPTIONS=<<-EOS
    url:
      name: URL
      notes: The URL to be used for health check
    header:
      name: Header
      notes: Header to check when performing health check, otherwise body is used
    expectedText:
      default: true
      name: Expected Text
      notes: Expected value of header or body text on a healthy node
    httpMethod:
      default: GET
      name: HTTP Method
      notes: HTTP verb to use for health check. GET and HEAD are supported
  EOS

  def build_report
    healthCheckUrl = "#{option(:url)}"
    if healthCheckUrl.empty?
      error("URL must be provided")
      return
    end

    httpVerb = "#{option(:httpMethod)}"
    header = "#{option(:header)}"
    expectedText = "#{option(:expectedText)}"
    if httpVerb.eql? "HEAD"
      response = Net::HTTP.request_head(URI.parse(healthCheckUrl))
    else
      response = Net::HTTP.get_response(URI.parse(healthCheckUrl))
    end
    case response
      when Net::HTTPSuccess
        if header.empty?
          isHealthy = response.body.eql? expectedText
        else
          isHealthy = response[header].eql? expectedText
        end
      else
        isHealthy = false
    end
    report(:healty => isHealthy)
  end
end