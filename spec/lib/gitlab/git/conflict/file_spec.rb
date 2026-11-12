# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Git::Conflict::File, feature_category: :source_code_management do
  let(:conflict) { { ancestor: { path: 'ancestor' }, theirs: { path: 'foo', mode: 33188 }, ours: { path: 'foo', mode: 33188 } } }
  let(:invalid_content) { described_class.new(nil, nil, conflict, (+"a\xC4\xFC").force_encoding(Encoding::ASCII_8BIT)) }
  let(:valid_content) { described_class.new(nil, nil, conflict, (+"Espa\xC3\xB1a").force_encoding(Encoding::ASCII_8BIT)) }

  describe '#lines' do
    context 'when the content contains non-UTF-8 characters' do
      it 'raises UnsupportedEncoding' do
        expect { invalid_content.lines }
          .to raise_error(described_class::UnsupportedEncoding)
      end
    end

    context 'when the content can be converted to UTF-8' do
      it 'sets lines to the lines' do
        expect(valid_content.lines).to eq([{
          full_line: 'España',
          type: nil,
          line_obj_index: 0,
          line_old: 1,
          line_new: 1
        }])
      end

      it 'sets the type to text' do
        expect(valid_content.type).to eq('text')
      end
    end
  end

  describe '#content' do
    context 'when the content contains non-UTF-8 characters' do
      it 'raises UnsupportedEncoding' do
        expect { invalid_content.content }
          .to raise_error(described_class::UnsupportedEncoding)
      end
    end

    context 'when the content can be converted to UTF-8' do
      it 'returns a valid UTF-8 string' do
        expect(valid_content.content).to eq('España')
        expect(valid_content.content).to be_valid_encoding
        expect(valid_content.content.encoding).to eq(Encoding::UTF_8)
      end
    end
  end

  describe '#resolve_lines' do
    let(:raw_content) do
      <<~CONTENT.chomp
        before
        <<<<<<< foo
        ours
        =======
        theirs
        >>>>>>> foo
        after
      CONTENT
    end

    let(:conflict_file) { described_class.new(nil, nil, conflict, raw_content) }
    let(:conflict_line) { conflict_file.lines.find { |line| line[:type] } }
    let(:section_id) { conflict_file.line_code(conflict_line) }

    it 'keeps only the new lines and lines without a type for the head resolution' do
      resolved = conflict_file.resolve_lines(section_id => 'head')

      expect(resolved.pluck(:full_line)).to eq(%w[before ours after])
    end

    it 'keeps only the old lines and lines without a type for the origin resolution' do
      resolved = conflict_file.resolve_lines(section_id => 'origin')

      expect(resolved.pluck(:full_line)).to eq(%w[before theirs after])
    end

    it 'raises ResolutionError when the resolution for a section is missing' do
      expect { conflict_file.resolve_lines({}) }
        .to raise_error(Gitlab::Git::Conflict::Resolver::ResolutionError, /Missing resolution for section ID/)
    end
  end

  describe '#path' do
    it 'returns our_path' do
      expect(valid_content.path).to eq(conflict[:ours][:path])
    end

    context 'when our_path is not present' do
      let(:conflict) { { ancestor: { path: 'ancestor' }, theirs: { path: 'theirs', mode: 33188 }, ours: { path: '', mode: 0 } } }

      it 'returns their_path' do
        expect(valid_content.path).to eq(conflict[:theirs][:path])
      end
    end
  end
end
