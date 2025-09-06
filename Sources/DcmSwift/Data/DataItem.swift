//
//  DataItem.swift
//  DICOM Test
//
//  Created by Rafael Warnault, OPALE on 18/10/2017.
//  Copyright © 2017 OPALE, Rafaël Warnault. All rights reserved.
//

import Foundation

/**
 `DataItem` are used in `DataSequence` to organize the nesting of `DataElement` objects.
 
 TODO: make DataItem inherit from DataSet to behave more like a collection?
 
 http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_7.5.html
 */
public class DataItem: DataElement {
    public var elements:[DataElement]   = []
    
    override public var name:String {
        return "Item"
    }
    
    
    
    override public func toJSON() -> String {
        var val = super.toJSON()
        
        if self.elements.count > 0 {
            val = val + ", " + elements.map { $0.toJSON() }.joined(separator: ", ")
        }
        
        return val
    }
    
    
    override public var isEditable:Bool  {
        return false
    }
    
    /**
     Get Data Element by name
     */
    public func element(withName name:String) -> DataElement? {
        for elem in elements {
            if elem.name == name {
                return elem
            }
        }
        
        return nil
    }
}
