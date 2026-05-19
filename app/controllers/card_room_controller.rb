class CardRoomController < ApplicationController
  layout 'card_room'

  def index
    @tables = Table.where(game_type: 'nl_holdem').order(:name)
  end

  def show
    @table = Table.find_by!(slug: params[:slug])
  end
end
