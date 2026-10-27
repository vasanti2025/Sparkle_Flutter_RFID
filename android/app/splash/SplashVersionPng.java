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
    }

    private SplashVersionPng() {}
}
