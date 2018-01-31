require 'json'
require 'open3'

RSpec.describe 'JoshuaScript' do
  def js(program, *outputs)
    executable = File.expand_path '../bin/joshuascript', __dir__
    out, err, status = Open3.capture3 executable, stdin_data: program
    expect(status).to be_success
    expect(err).to be_empty
    # matcher = Regexp.new Regexp.escape(program).gsub(/(?<=\d)\d(?=\\ ms)/, '\\d')
    expect(out.lines.length).to eq outputs.length
    out.lines.zip(outputs).each do |line, (expected_lineno, ms_matcher)|
      actual_lineno, ms = JSON.parse line
      expect(actual_lineno).to eq expected_lineno
      expect(ms).to match ms_matcher
    end
  end

  it 'passes ze exampel' do
    js <<~JS, [2, /\A0 ms\z/], [10, /\A0 ms\z/], [5, /\A1\d ms\z/], [7, /\A3\d ms\z/]
    // No time has passed since we started
    showTime() // 0 ms

    setTimeout(() => {
      showTime() // 10 ms
      setTimeout(20)
      showTime() // 30 ms
    }, 10)

    showTime() // 0 ms
    JS
  end
end
