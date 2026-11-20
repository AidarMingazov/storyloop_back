# Shows which provider keys are set (never prints values).
#   docker compose exec web ruby script/ai_probe/keys.rb
require_relative "lib"

puts Probe.keys_status(%w[DEEPSEEK_API_KEY DASHSCOPE_API_KEY ARK_API_KEY MINIMAX_API_KEY OPENROUTER_API_KEY ANTHROPIC_API_KEY])
puts "SEEDREAM_MODEL=#{ENV['SEEDREAM_MODEL'] || '(default)'}, QWEN_BASE_URL=#{ENV['QWEN_BASE_URL'] || '(default)'}"
