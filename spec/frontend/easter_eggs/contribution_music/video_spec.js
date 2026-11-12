import { drawLogo } from '~/easter_eggs/contribution_music/video';

describe('drawLogo', () => {
  const originalPixelRatio = window.devicePixelRatio;
  const originalVisualViewport = window.visualViewport;
  let image;
  let canvas;

  beforeEach(() => {
    image = new Image();
    Object.defineProperties(image, {
      naturalWidth: { value: 1024 },
      naturalHeight: { value: 512 },
    });

    jest.spyOn(window, 'Image').mockImplementation(() => image);

    URL.createObjectURL = jest.fn().mockReturnValue('blob:logo');
    URL.revokeObjectURL = jest.fn();

    // Create mock logo pixel data.
    const data = new Uint8ClampedArray(256 * 256 * 4);
    for (let y = 80; y < 200; y += 1) {
      for (let x = 40; x < 220; x += 1) {
        if (x < 80 || y < 180) {
          data[(y * 256 + x) * 4 + 3] = 255;
        }
      }
    }

    jest.spyOn(CanvasRenderingContext2D.prototype, 'getImageData').mockReturnValue({ data });

    canvas = document.createElement('canvas');
  });

  afterEach(() => {
    window.devicePixelRatio = originalPixelRatio;
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: originalVisualViewport,
    });
  });

  it.each([
    { devicePixelRatio: 1, visualScale: 1 },
    { devicePixelRatio: 2, visualScale: 1 },
    { devicePixelRatio: 2, visualScale: 1.5 },
  ])(
    'crops a rasterized logo at pixel ratio $devicePixelRatio and visual scale $visualScale',
    async ({ devicePixelRatio, visualScale }) => {
      const ratio = devicePixelRatio * visualScale;
      window.devicePixelRatio = devicePixelRatio;
      Object.defineProperty(window, 'visualViewport', {
        configurable: true,
        value: { scale: visualScale },
      });

      const drawing = drawLogo(canvas, 20);
      image.onload();
      await drawing;

      const context = canvas.getContext('2d');
      const [raster, ...coordinates] = context.drawImage.mock.calls[0];
      expect(raster).toBeInstanceOf(HTMLCanvasElement);
      expect(raster.width).toBe(1024);
      expect(raster.height).toBe(512);
      expect(raster.getContext('2d').drawImage).toHaveBeenCalledWith(image, 0, 0);
      for (const samplingContext of CanvasRenderingContext2D.prototype.getImageData.mock
        .instances) {
        expect(samplingContext.drawImage).toHaveBeenCalledWith(raster, 0, 0, 256, 256);
      }

      expect(coordinates).toEqual([160, 160, 720, 240, 0, 0, 60 * ratio, 20 * ratio]);

      expect(canvas.width).toBe(60 * ratio);
      expect(canvas.height).toBe(20 * ratio);
      expect(canvas.style.width).toBe('60px');
      expect(canvas.style.height).toBe('20px');

      expect(parseFloat(canvas.style.marginBottom)).toBeCloseTo(-10 / 3);
    },
  );
});
