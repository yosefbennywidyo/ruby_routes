# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyRoutes::Route::CheckHelpers do
  let(:dummy_class) do
    Class.new do
      include RubyRoutes::Route::CheckHelpers
    end
  end

  let(:instance) { dummy_class.new }

  describe '#check_range' do
    let(:constraint) { { range: 1..10 } }

    it 'raises an error for values outside the range' do
      expect { instance.check_range(constraint, '11') }.to raise_error(RubyRoutes::ConstraintViolation, 'Value not in allowed range')
    end

    it 'does not raise an error for values within the range' do
      expect { instance.check_range(constraint, '5') }.not_to raise_error
    end

    it 'raises an error for non-numeric strings' do
      expect { instance.check_range(constraint, 'abc') }.to raise_error(RubyRoutes::ConstraintViolation, 'Value not in allowed range')
    end

    it 'raises an error for nil values' do
      expect { instance.check_range(constraint, nil) }.to raise_error(RubyRoutes::ConstraintViolation, 'Value not in allowed range')
    end

    it 'does not raise an error for numeric strings within the range' do
      expect { instance.check_range(constraint, '10') }.not_to raise_error
    end

    context 'when range includes 0' do
      let(:constraint) { { range: 0..10 } }

      it 'still raises for non-numeric strings' do
        expect { instance.check_range(constraint, 'abc') }.to raise_error(RubyRoutes::ConstraintViolation, 'Value not in allowed range')
      end

      it 'still raises for nil' do
        expect { instance.check_range(constraint, nil) }.to raise_error(RubyRoutes::ConstraintViolation, 'Value not in allowed range')
      end
    end

    it 'raises for floats' do
      expect { instance.check_range({ range: 1..10 }, '3.14') }.to raise_error(RubyRoutes::ConstraintViolation, 'Value not in allowed range')
    end

    it 'honors exclusive upper bound' do
      expect { instance.check_range({ range: 1...3 }, '3') }.to raise_error(RubyRoutes::ConstraintViolation, 'Value not in allowed range')
    end
  end
end
