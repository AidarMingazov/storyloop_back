# Messenger and social crawlers that fetch a shared link to draw its preview card.
module LinkPreview
  CRAWLERS = /TelegramBot|WhatsApp|facebookexternalhit|Facebot|Twitterbot|Slackbot|Discordbot|LinkedInBot|vkShare|
              Viber|SkypeUriPreview|redditbot|Pinterest|Embedly|Googlebot|bingbot|YandexBot|Applebot|Iframely/x

  module_function

  def crawler?(user_agent) = user_agent.to_s.match?(CRAWLERS)
end
