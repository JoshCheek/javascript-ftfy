require 'json'
require 'open3'

RSpec.describe 'JoshuaScript' do
  def js(program)
    executable = File.expand_path '../bin/joshuascript', __dir__
    Open3.capture3 executable, stdin_data: program
  end

  it 'passes ze exampel' do
    out, err, status = js <<~JS
    // No time has passed since we started
    showTime() // 0 ms

    setTimeout(() => {
      showTime() // 10 ms
      setTimeout(20)
      showTime() // 30 ms
    }, 10)

    showTime() // 0 ms
    JS

    expecteds = [
      [ 2, /\A0 ms\z/],
      [10, /\A0 ms\z/],
      [ 5, /\A1\d ms\z/],
      [ 7, /\A3\d ms\z/],
    ]
    expect(status).to be_success
    expect(err).to be_empty
    expect(out.lines.length).to eq expecteds.length
    out.lines.zip(expecteds).each do |line, (expected_lineno, ms_matcher)|
      actual_lineno, ms = JSON.parse line
      expect(actual_lineno).to eq expected_lineno
      expect(ms).to match ms_matcher
    end
  end

  it 'has readable error messages' do
    out, err, status = js '1 +'
    expect(status).to_not eq 0
    expect(out).to eq ''
    expect(err).to match /SyntaxError/
    expect(err).to match /Line 1/
  end
end
