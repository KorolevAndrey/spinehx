/*******************************************************************************
 * Copyright (c) 2013, Esoteric Software
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 ******************************************************************************/

package spinehx;

import spinehx.attachments.RegionAttachment;
import spinehx.attachments.RegionSequenceAttachment;
import spinehx.attachments.AttachmentType;
import spinehx.attachments.Attachment;
import spinehx.attachments.Mode;
import spinehx.attachments.AttachmentLoader;
import spinehx.Animation;
import spinehx.ex.SerializationException;
import spinehx.ex.IllegalArgumentException;
import spinehx.ex.RuntimeException;
import spinehx.attachments.AtlasAttachmentLoader;
import spinehx.atlas.TextureAtlas;
import haxe.Json;
import Reflect;
using Reflect;

class SkeletonJson {

    public static inline var TIMELINE_SCALE = "scale";
    public static inline var TIMELINE_ROTATE = "rotate";
    public static inline var TIMELINE_TRANSLATE = "translate";
    public static inline var TIMELINE_ATTACHMENT = "attachment";
    public static inline var TIMELINE_COLOR = "color";

    private var  json:Json;
    private var attachmentLoader: AttachmentLoader;
    private var scale:Float = 1;

    public function new(atlas:TextureAtlas) {
        attachmentLoader = new AtlasAttachmentLoader(atlas);
    }

//    public SkeletonJson (AttachmentLoader attachmentLoader) {
//        this.attachmentLoader = attachmentLoader;
//    }

    public function getScale ():Float {
        return scale;
    }

    /** Scales the bones, images, and animations as they are loaded. */
    public function setScale (scale:Float):Void {
        this.scale = scale;
    }

    public function readSkeletonData (name:String, fileData:String):SkeletonData {
        if (fileData == null) throw new IllegalArgumentException("file cannot be null.");

        var skeletonData = new SkeletonData();
        skeletonData.setName(name);

        var root:Dynamic = Json.parse(fileData); //OrderedMap<String, ?> root = json.fromJson(OrderedMap.class, file);

        // Bones.
        for (boneMap in cast(root.getProperty("bones"), Array<Dynamic>)) {
            var parent:BoneData = null;
            var parentName:String = cast(boneMap.getProperty("parent"));
            if (parentName != null) {
                parent = skeletonData.findBone(parentName);
                if (parent == null) throw new SerializationException("Parent bone not found: " + parentName);
            }
            var boneData = new BoneData(cast(boneMap.getProperty("name"), String), parent);
            boneData.length = getFloat(boneMap, "length", 0) * scale;
            boneData.x = getFloat(boneMap, "x", 0) * scale;
            boneData.y = getFloat(boneMap, "y", 0) * scale;
            boneData.rotation = getFloat(boneMap, "rotation", 0);
            boneData.scaleX = getFloat(boneMap, "scaleX", 1);
            boneData.scaleY = getFloat(boneMap, "scaleY", 1);
            skeletonData.addBone(boneData);
        }

        // Slots.
        var slots = cast(root.getProperty("slots"), Array<Dynamic>);
        if (slots != null) {
            for (slotMap in slots) {
                var slotName:String = cast(slotMap.getProperty("name"));
                var boneName:String = cast(slotMap.getProperty("bone"));
                var boneData:BoneData = skeletonData.findBone(boneName);
                if (boneData == null) throw new SerializationException("Slot bone not found: " + boneName);
                var slotData = new SlotData(slotName, boneData);

                var color:String = cast(slotMap.getProperty("color"));
                if (color != null) slotData.getColor().set2(Color.valueOf(color));

                slotData.setAttachmentName(cast(slotMap.getProperty("attachment"), String));

                skeletonData.addSlot(slotData);
            }
        }

        // Skins.
        var skinsMap:Dynamic = root.getProperty("skins");
        if (skinsMap != null) {
            for (skinKey in skinsMap.fields()) {
                var skinValue:Dynamic  = skinsMap.getProperty(skinKey);
                var skin = new Skin(skinKey);
                for (slotKey in skinValue.fields()) {
                    var slotValue:Dynamic = skinValue.getProperty(slotKey);
                    var slotIndex:Int = skeletonData.findSlotIndex(slotKey);
                    for (attachmentKey in slotValue.fields()) {
                        var attachmentValue = slotValue.getProperty(attachmentKey);
                        var attachment:Attachment = readAttachment(skin, attachmentKey, attachmentValue);
                        if (attachment != null) skin.addAttachment(slotIndex, attachmentKey, attachment);
                    }
                }
                skeletonData.addSkin(skin);
                if (skin.name == "default") skeletonData.setDefaultSkin(skin);
            }
        }

        // Animations.
        var animationMap:Dynamic = root.getProperty("animations");
        if (animationMap != null) {
            for (key in animationMap.fields())
            readAnimation(key, animationMap.getProperty(key), skeletonData);
        }

//        skeletonData.bones.shrink();
//        skeletonData.slots.shrink();
//        skeletonData.skins.shrink();
//        skeletonData.animations.shrink();
        return skeletonData;
    }

    private function readAttachment (skin:Skin, name:String, map:Dynamic):Attachment {
        var name2:String = cast(map.getProperty("name"));
        name = name2 != null ? name2 : name;

        var typeStr:String = cast(map.getProperty("type"));
        var type:AttachmentType = AttachmentTypes.valueOf(typeStr, AttachmentType.region);
        var attachment:Attachment = attachmentLoader.newAttachment(skin, type, name);

        if (Std.is(attachment, RegionSequenceAttachment)) {
            var regionSequenceAttachment = cast(attachment, RegionSequenceAttachment);

            var fps:Float = getFloat(map, "fps", -1);
            if (fps == -1) throw new SerializationException("Region sequence attachment missing fps: " + name);
            regionSequenceAttachment.setFrameTime(fps);

            var modeString = cast(map.getProperty("mode"),String);
            regionSequenceAttachment.setMode(Modes.valueOf(modeString, Mode.forward));
        }

        if (Std.is(attachment, RegionAttachment)) {
            var regionAttachment = cast(attachment, RegionAttachment);
            regionAttachment.setX(getFloat(map, "x", 0) * scale);
            regionAttachment.setY(getFloat(map, "y", 0) * scale);
            regionAttachment.setScaleX(getFloat(map, "scaleX", 1));
            regionAttachment.setScaleY(getFloat(map, "scaleY", 1));
            regionAttachment.setRotation(getFloat(map, "rotation", 0));
            regionAttachment.setWidth(getFloat(map, "width", 32) * scale);
            regionAttachment.setHeight(getFloat(map, "height", 32) * scale);
            regionAttachment.updateOffset();
        }

        return attachment;
    }

    private function getFloat (map:Dynamic, name:String, defaultValue:Float=0):Float {
        var value:Dynamic = map.getProperty(name);
        if (value == null) return defaultValue;
        if (Std.is(value, Int)) return cast(value, Int);
        return cast(value, Float);
    }

    private function getFloatAt (array:Array<Dynamic>, index:Int):Float {
        var value:Dynamic = array[index];
        if (value == null) return 0;
        if (Std.is(value, Int)) return cast(value, Int);
        return cast(value, Float);
    }

    private function readAnimation (name:String, map:Dynamic, skeletonData:SkeletonData):Void {
        var timelines = new Array<Timeline>();
        var duration:Float = 0;

        var bonesMap:Dynamic = map.getProperty("bones");
        if (bonesMap != null) {
            for (boneName in bonesMap.fields()) {
                var timelineMap:Dynamic = bonesMap.getProperty(boneName);
                var boneIndex:Int = skeletonData.findBoneIndex(boneName);
                if (boneIndex == -1) throw new SerializationException("Bone not found: " + boneName);

                for (timelineName in timelineMap.fields()) {
                var values = cast(timelineMap.getProperty(timelineName), Array<Dynamic>) ;

                if (timelineName == TIMELINE_ROTATE) {
                    var timeline = new RotateTimeline(values.length);
                    timeline.setBoneIndex(boneIndex);

                    var frameIndex:Int = 0;
                    for (valueMap in values) {
                        var time:Float = getFloat(valueMap, "time");
                        timeline.setFrame(frameIndex, time, getFloat(valueMap, "angle"));
                        readCurve(timeline, frameIndex, valueMap);
                        frameIndex++;
                    }
                    timelines.push(timeline);
                    duration = Math.max(duration, timeline.getFrames()[timeline.getFrameCount() * 2 - 2]);

                } else if (timelineName == TIMELINE_TRANSLATE || timelineName == TIMELINE_SCALE) {
                    var timeline:TranslateTimeline;
                    var timelineScale:Float = 1;
                    if (timelineName == TIMELINE_SCALE)
                        timeline = new ScaleTimeline(values.length);
                    else {
                        timeline = new TranslateTimeline(values.length);
                        timelineScale = scale;
                    }
                    timeline.setBoneIndex(boneIndex);

                    var frameIndex:Int = 0;
                    for (valueMap in values) {
                        var time:Float = getFloat(valueMap, "time");
                        var x:Float = getFloat(valueMap, "x", 0);
                        var y:Float = getFloat(valueMap, "y", 0);
                        timeline.setFrame(frameIndex, time, (x * timelineScale), (y * timelineScale));
                        readCurve(timeline, frameIndex, valueMap);
                        frameIndex++;
                    }
                    timelines.push(timeline);
                    duration = Math.max(duration, timeline.getFrames()[timeline.getFrameCount() * 3 - 3]);

                } else
                    throw new RuntimeException("Invalid timeline type for a bone: " + timelineName + " (" + boneName + ")");
                }
            }
        }

        var slotsMap:Dynamic = map.getProperty("slots");
        if (slotsMap != null) {
            for (slotName in slotsMap.fields()) {
                var timelineMap:Dynamic = slotsMap.getProperty(slotName);
                var slotIndex:Int = skeletonData.findSlotIndex(slotName);

                for (timelineName in timelineMap.fields()) {
                    var values = cast(timelineMap.getProperty(timelineName), Array<Dynamic>);
                    if (timelineName == TIMELINE_COLOR) {
                        var timeline = new ColorTimeline(values.length);
                        timeline.setSlotIndex(slotIndex);

                        var frameIndex:Int = 0;
                        for (valueMap in values) {
                            var time:Float = getFloat(valueMap, "time");
                            var color:Color = Color.valueOf(cast(valueMap.getProperty("color"), String));
                            timeline.setFrame(frameIndex, time, color.r, color.g, color.b, color.a);
                            readCurve(timeline, frameIndex, valueMap);
                            frameIndex++;
                        }
                        timelines.push(timeline);
                        duration = Math.max(duration, timeline.getFrames()[timeline.getFrameCount() * 5 - 5]);

                    } else if (timelineName == TIMELINE_ATTACHMENT) {
                        var timeline = new AttachmentTimeline(values.length);
                        timeline.setSlotIndex(slotIndex);

                        var frameIndex:Int = 0;
                        for (valueMap in values) {
                            var time:Float = getFloat(valueMap, "time");
                            timeline.setFrame(frameIndex++, time, cast(valueMap.getProperty("name"), String));
                        }
                        timelines.push(timeline);
                        duration = Math.max(duration, timeline.getFrames()[timeline.getFrameCount() - 1]);

                    } else
                        throw new RuntimeException("Invalid timeline type for a slot: " + timelineName + " (" + slotName + ")");
                }
            }
        }

        //timelines.shrink();
        skeletonData.addAnimation(new Animation(name, timelines, duration));
    }

    private function readCurve (timeline:CurveTimeline, frameIndex:Int, valueMap:Dynamic):Void {
        var curveObject = valueMap.getProperty("curve");
        if (curveObject == null) return;
        if (curveObject == "stepped")
            timeline.setStepped(frameIndex);
        else if (Std.is(curveObject, Array)) {
            var curve = cast(curveObject, Array<Dynamic>);
            timeline.setCurve(frameIndex, getFloatAt(curve, 0), getFloatAt(curve, 1), getFloatAt(curve, 2), getFloatAt(curve, 3));
        }
    }
}