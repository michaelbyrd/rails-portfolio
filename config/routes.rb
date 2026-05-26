Rails.application.routes.draw do
  root "pages#home"

  get "up" => "rails/health#show", as: :rails_health_check

  get  '/ctci',              to: 'ctci#index',          as: :ctci

  get '/card_room',       to: 'card_room#index', as: :card_room
  get '/card_room/:slug', to: 'card_room#show',  as: :card_room_table

  get  '/audio',             to: 'audio#index',        as: :audio
  get  '/audio/new',         to: 'audio#new_song',     as: :audio_new
  post '/audio/songs',       to: 'audio/songs#create', as: :audio_songs
  get  '/audio/songs/:slug', to: 'audio/songs#show',   as: :audio_song
end

