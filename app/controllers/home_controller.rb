class HomeController < ApplicationController
  allow_unauthenticated_access

  def show
    @pairs = LanguagePair.active.includes(series: :episodes).order(:code)
  end
end
