# The reader's chrome (wave Р2): the language pill and the settings sheet.
module ReaderHelper
  # The same episode in every language it exists in — the original and its translations (7.8) —
  # that this reader may open, the current one included. One element means there is nothing to switch to.
  def reader_editions(episode, reader)
    root = episode.origin_episode || episode
    family = [ root, *root.translations.includes(series: :language_pair) ]
    family.select { |edition| edition == episode || StoryAccess.new(edition, reader, via_link: true).readable? }
          .sort_by { |edition| edition.series.language_pair.code }
  end

  # "Korean", "Корейский": the name of a learning language in the interface language.
  def language_name(code) = t("reader.languages.#{code}", default: code.to_s.upcase)

  # <button role="switch"> wired to reader#togglePref; the controller sets aria-checked from the device's prefs.
  def reader_switch(pref, label)
    tag.button(type: "button", class: "switch", role: "switch", id: "pref_#{pref}", aria: { checked: false },
               data: { reader_target: "prefSwitch", pref:, action: "reader#togglePref" }) do
      tag.span(label) + tag.i(class: "switch-knob", aria: { hidden: true })
    end
  end

  # One row of chips wired to reader#choosePref: `options` is { value => label }.
  def reader_choice(pref, label, options)
    tag.div(class: "reader-set-row", role: "group", aria: { label: }) do
      tag.p(label, class: "reader-set-label") +
        tag.div(class: "flex flex-wrap gap-1.5") do
          safe_join(options.map do |value, text|
            tag.button(text, type: "button", class: "chip", id: "pref_#{pref}_#{value}", aria: { pressed: false },
                             data: { reader_target: "prefChoice", pref:, value:, action: "reader#choosePref" })
          end)
        end
    end
  end
end
