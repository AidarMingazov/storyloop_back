module Admin
  class TokensController < BaseController
    before_action :set_token, only: %i[edit update destroy]

    def new
      @bubble = Bubble.find(params[:bubble_id])
      @token = @bubble.tokens.build
      @form = TokenForm.new(token: @token)
    end

    def create
      @bubble = Bubble.find(params[:bubble_id])
      @token = @bubble.tokens.build
      @form = TokenForm.new(token: @token, **form_params)
      if @form.save
        redirect_to admin_episode_path(@bubble.episode, anchor: dom_id(@bubble.panel)), notice: "Токен добавлен"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @form = TokenForm.new(token: @token)
    end

    def update
      @form = TokenForm.new(token: @token, **form_params)
      if @form.save
        redirect_to admin_episode_path(@token.bubble.episode, anchor: dom_id(@token.bubble.panel)), notice: "Токен сохранён"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @token.destroy!
      redirect_to admin_episode_path(@token.bubble.episode, anchor: dom_id(@token.bubble.panel)),
                  notice: "Токен удалён", status: :see_other
    end

    private
      def set_token
        @token = Token.find(params[:id])
      end

      def form_params
        params.expect(token_form: TokenForm::FIELDS).to_h.symbolize_keys
      end
  end
end
