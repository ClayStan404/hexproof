// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import com.thoughtworks.xstream.XStream;
import java.io.StringReader;
import java.util.Arrays;
import org.xmlpull.v1.XmlPullParser;
import org.xmlpull.v1.XmlPullParserFactory;

public final class XmlDependencyRegressionTest {
    public static void main(String[] args) throws Exception {
        XmlPullParser parser = XmlPullParserFactory.newInstance().newPullParser();
        if (!parser.getClass().getName().equals("io.github.xstream.mxparser.MXParser")) {
            throw new AssertionError("XMLPull parser provider changed: " + parser.getClass());
        }
        parser.setInput(new StringReader("<root key='value'>&lt;card&gt;<![CDATA[ & token ]]></root>"));
        if (parser.nextTag() != XmlPullParser.START_TAG
                || !parser.getName().equals("root")
                || !parser.getAttributeValue(null, "key").equals("value")
                || !parser.nextText().equals("<card> & token ")) {
            throw new AssertionError("XMLPull parsing regression");
        }
        XStream xstream = new XStream();
        String[] expected = {"Forest", "<token>&\"", "\u4e00\u5f20\u724c"};
        Object actual = xstream.fromXML(xstream.toXML(expected));
        if (!(actual instanceof String[]) || !Arrays.equals(expected, (String[]) actual)) {
            throw new AssertionError("XStream XML round-trip regression");
        }
        System.out.println("XMLPull provider and XStream read/write regressions passed.");
    }
}
