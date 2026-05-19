class Song < ApplicationRecord
  DEFAULT_STATE = {
    'grid'        => Array.new(12) { Array.new(16, false) },
    'kick'        => Array.new(16, false),
    'kick_active' => false,
    'bpm'         => 120,
    'waveform'    => 'sine',
    'decay'       => 0.4,
    'reverb'      => 20,
    'volume'      => -6
  }.freeze

  before_create :generate_slug

  after_initialize do
    self.state = DEFAULT_STATE.deep_dup if state.blank?
  end

  def apply_diff(data)
    s = state.deep_dup
    case data['type']
    when 'toggle'
      s['grid'][data['row'].to_i][data['step'].to_i] = data['value']
    when 'kick_toggle'
      s['kick'][data['step'].to_i] = data['value']
    when 'kick_active'
      s['kick_active'] = data['value']
    when 'bpm'
      s['bpm'] = data['value'].to_i
    when 'waveform'
      s['waveform'] = data['value'].to_s
    when 'decay'
      s['decay'] = data['value'].to_f
    when 'reverb'
      s['reverb'] = data['value'].to_i
    when 'volume'
      s['volume'] = data['value'].to_i
    when 'clear'
      s['grid'] = Array.new(12) { Array.new(16, false) }
      s['kick'] = Array.new(16, false)
    when 'full_sync'
      s['grid']        = data['grid']        if data['grid']
      s['kick']        = data['kick']        if data['kick']
      s['kick_active'] = data['kick_active'] unless data['kick_active'].nil?
    end
    update!(state: s)
  end

  private

  def generate_slug
    loop do
      self.slug = SecureRandom.alphanumeric(8).downcase
      break unless Song.exists?(slug: slug)
    end
  end
end
