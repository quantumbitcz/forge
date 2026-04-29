import { describe, it, expect } from 'vitest';
import { health } from './index.js';

describe('health', () => {
  it('returns ok', () => {
    expect(health()).toEqual({ status: 'ok' });
  });
});
