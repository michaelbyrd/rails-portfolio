FactoryBot.define do
  factory :song do
    sequence(:slug) { |n| "test#{n.to_s.rjust(4, '0')}" }
    state { Song::DEFAULT_STATE.deep_dup }
  end
end