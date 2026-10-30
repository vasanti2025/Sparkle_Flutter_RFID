import java.awt.Color;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

/** Draws the splash "Version x.y.z" from the app bundle versionName. */
public final class SplashVersionPng {
    public static void main(String[] args) throws Exception {
        System.setProperty("java.awt.headless", "true");
        if (args.length < 2) {
            throw new IllegalArgumentException("usage: SplashVersionPng <versionName> <png>");
        }
        String text = "Version " + args[0];
        File out = new File(args[1]);
        File parent = out.getParentFile();
        if (parent != null) {
            parent.mkdirs();
        }
        int width = 1000;
        int height = 400;
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = image.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setFont(new Font("SansSerif", Font.PLAIN, 96));
        int textWidth = g.getFontMetrics().stringWidth(text);
        int x = Math.max(0, (width - textWidth) / 2);
        int y = (height - g.getFontMetrics().getHeight()) / 2 + g.getFontMetrics().getAscent();
        g.setColor(new Color(0x46, 0x46, 0x4A));
        g.drawString(text, x, y);
        g.dispose();
        ImageIO.write(image, "png", out);

        File dir = out.getParentFile();
        writeLines(
                new File(dir, "splash_caption.png"),
                1200,
                320,
                new String[] {"Every piece matters.", "Make every moment count."},
                new Color[] {new Color(0xD9, 0xD6, 0xCE), new Color(0xE6, 0xC4, 0x77)},
                72
        );
        writeLines(
                new File(dir, "splash_footer.png"),
                1200,
                240,
                new String[] {
                    "Intelligent Jewellery Operations",
                    "Loyal String International Pvt Ltd."
                },
                new Color[] {new Color(0x96, 0x93, 0x8C), new Color(0x96, 0x93, 0x8C)},
                46
        );
        if (args.length >= 3) {
            writeCenteredBlock(new File(args[2]), new File(dir, "splash_block.png"));
            writeFullScreen(new File(args[2]), new File(dir, "splash_screen.png"));
        }
    }

    /** Logo plus every splash line, in one centered block so the company name is not clipped. */
    private static void writeCenteredBlock(File logoFile, File out) throws Exception {
        int width = 900;
        BufferedImage logo = ImageIO.read(logoFile);
        int logoW = 320;
        int logoH = Math.max(1, (int) Math.round(logo.getHeight() * (logoW / (double) logo.getWidth())));
        Font captionFont = new Font("SansSerif", Font.PLAIN, 40);
        Font footerFont = new Font("SansSerif", Font.PLAIN, 32);
        BufferedImage probe = new BufferedImage(1, 1, BufferedImage.TYPE_INT_ARGB);
        Graphics2D probeG = probe.createGraphics();
        probeG.setFont(captionFont);
        int captionLine = probeG.getFontMetrics().getHeight();
        probeG.setFont(footerFont);
        int footerLine = probeG.getFontMetrics().getHeight();
        probeG.dispose();
        int top = 8;
        int gapAfterLogo = 28;
        int gapBeforeFooter = 36;
        int bottom = 8;
        int height = top + logoH + gapAfterLogo + (captionLine * 2) + gapBeforeFooter + (footerLine * 2) + bottom;
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = image.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);
        g.drawImage(logo, (width - logoW) / 2, top, logoW, logoH, null);
        int y = top + logoH + gapAfterLogo;
        g.setFont(captionFont);
        y = drawLines(g, y, width, new String[] {
            "Every piece matters.",
            "Make every moment count."
        }, new Color[] {
            new Color(0xD9, 0xD6, 0xCE),
            new Color(0xE6, 0xC4, 0x77)
        });
        y += gapBeforeFooter;
        g.setFont(footerFont);
        drawLines(g, y, width, new String[] {
            "Intelligent Jewellery Operations",
            "Loyal String International Pvt Ltd."
        }, new Color[] {
            new Color(0x96, 0x93, 0x8C),
            new Color(0x96, 0x93, 0x8C)
        });
        g.dispose();
        ImageIO.write(image, "png", out);
    }

    /** Icon at the vertical center. Company lines stay near the bottom. */
    private static void writeFullScreen(File logoFile, File out) throws Exception {
        int width = 1080;
        int height = 1920;
        BufferedImage logo = ImageIO.read(logoFile);
        int logoW = 520;
        int logoH = Math.max(1, (int) Math.round(logo.getHeight() * (logoW / (double) logo.getWidth())));
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = image.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);
        g.setColor(Color.BLACK);
        g.fillRect(0, 0, width, height);
        int logoTop = (height - logoH) / 2;
        g.drawImage(logo, (width - logoW) / 2, logoTop, logoW, logoH, null);
        g.setFont(new Font("SansSerif", Font.PLAIN, 42));
        int y = logoTop + logoH + 28;
        drawLines(g, y, width, new String[] {
            "Every piece matters.",
            "Make every moment count."
        }, new Color[] {
            new Color(0xD9, 0xD6, 0xCE),
            new Color(0xE6, 0xC4, 0x77)
        });
        g.setFont(new Font("SansSerif", Font.PLAIN, 32));
        drawLines(g, height - 250, width, new String[] {
            "Intelligent Jewellery Operations",
            "Loyal String International Pvt Ltd."
        }, new Color[] {
            new Color(0x96, 0x93, 0x8C),
            new Color(0x96, 0x93, 0x8C)
        });
        g.dispose();
        ImageIO.write(image, "png", out);
    }

    private static int drawLines(Graphics2D g, int y, int width, String[] lines, Color[] colors) {
        int lineHeight = g.getFontMetrics().getHeight();
        int baseline = y + g.getFontMetrics().getAscent();
        for (int i = 0; i < lines.length; i++) {
            g.setColor(colors[i]);
            int textWidth = g.getFontMetrics().stringWidth(lines[i]);
            g.drawString(lines[i], Math.max(0, (width - textWidth) / 2), baseline);
            baseline += lineHeight;
        }
        return y + (lineHeight * lines.length);
    }

    private static void writeLines(
            File out,
            int width,
            int height,
            String[] lines,
            Color[] colors,
            int fontSize
    ) throws Exception {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = image.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setFont(new Font("SansSerif", Font.PLAIN, fontSize));
        int lineHeight = g.getFontMetrics().getHeight();
        int block = lineHeight * lines.length;
        int y = (height - block) / 2 + g.getFontMetrics().getAscent();
        for (int i = 0; i < lines.length; i++) {
            g.setColor(colors[i]);
            int textWidth = g.getFontMetrics().stringWidth(lines[i]);
            int x = Math.max(0, (width - textWidth) / 2);
            g.drawString(lines[i], x, y);
            y += lineHeight;
        }
        g.dispose();
        ImageIO.write(image, "png", out);
    }

    private SplashVersionPng() {}
}
