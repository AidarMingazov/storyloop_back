import { Controller } from "@hotwired/stimulus"

// Loads posthog-js when a project key is configured and sends the two browser-only events.
// Every other funnel event is captured on the server with the same distinct id.
export default class extends Controller {
  connect() {
    const key = meta("posthog-key")
    if (!key || window.posthog?.__loaded) return

    loadPosthog()
    window.posthog.init(key, {
      api_host: meta("posthog-host"),
      person_profiles: "always",
      capture_pageview: "history_change",
      bootstrap: { distinctID: meta("analytics-distinct-id") }
    })
    window.posthog.register(context())
  }

  tokenTapped(event) {
    this.capture("token_tapped", { lexeme_id: event.detail.lexemeId, token_id: event.detail.tokenId, ...episodeProps(event) })
  }

  bubbleTranslated(event) {
    this.capture("bubble_translated", { bubble_id: event.detail.bubbleId, ...episodeProps(event) })
  }

  capture(name, properties) {
    window.posthog?.capture?.(name, { ...context(), ...properties })
  }
}

function meta(name) {
  return document.querySelector(`meta[name="${name}"]`)?.content
}

function context() {
  try { return JSON.parse(meta("analytics-context") || "{}") } catch { return {} }
}

function episodeProps(event) {
  const { pair, format, number, level, motion } = event.detail
  return { pair, format, episode_number: number, episode_level: level, motion } // motion: spike M.0, webtoon only
}

// Official PostHog loader stub: queues calls until array.js arrives from the PostHog CDN.
function loadPosthog() {
  !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="init capture register register_once register_for_session unregister unregister_for_session identify setPersonProperties group resetGroups reset get_distinct_id getGroups get_session_id alias set_config startSessionRecording stopSessionRecording opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing debug getFeatureFlag isFeatureEnabled onFeatureFlags".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[])
}
